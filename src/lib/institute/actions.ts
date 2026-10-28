"use server";

import { revalidatePath } from "next/cache";
import { getCurrentUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import {
  courseSchema, instituteApplicationSchema, parseFaculty, slugify,
} from "@/lib/validation/institute";
import type { ActionResult } from "@/lib/validation/auth";

const NOT_CONFIGURED: ActionResult = { ok: false, preview: true, error: "Supabase is not configured, so nothing was saved." };

async function context(): Promise<{ result: ActionResult } | { supabase: NonNullable<Awaited<ReturnType<typeof createClient>>>; user: NonNullable<Awaited<ReturnType<typeof getCurrentUser>>> }> {
  const supabase = await createClient();
  if (!supabase) return { result: NOT_CONFIGURED };
  const user = await getCurrentUser();
  if (!user) return { result: { ok: false, error: "Please log in first." } as ActionResult };
  return { supabase, user };
}

/** The institute the signed-in user belongs to (RLS limits this to their own memberships). */
async function myInstituteId(supabase: NonNullable<Awaited<ReturnType<typeof createClient>>>, userId: string) {
  const { data } = await supabase.from("institute_members").select("institute_id").eq("user_id", userId).limit(1).maybeSingle();
  return data?.institute_id as string | undefined;
}

/**
 * Creates the institute as a DRAFT (the only status RLS allows on insert), stores private contact details,
 * a first course + batch and faculty, then moves it to 'submitted' for admin review.
 * It never sets verification: only an admin can.
 */
export async function submitInstituteApplication(input: unknown): Promise<ActionResult> {
  const parsed = instituteApplicationSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  const ctx = await context();
  if ("result" in ctx) return ctx.result;
  const { supabase, user } = ctx;
  if (!user.roles.includes("institute")) return { ok: false, error: "Only institute accounts can submit an application." };
  if (await myInstituteId(supabase, user.id)) return { ok: false, error: "Your institute application already exists. Edit it from your dashboard." };

  const v = parsed.data;
  const exams = v.exams.split(",").map((e) => e.trim()).filter(Boolean).slice(0, 20);
  const slug = slugify(v.name);

  const { data: inst, error } = await supabase
    .from("institutes")
    .insert({ slug, name: v.name, tagline: v.tagline || null, about: v.about, city: v.city, address: v.address, pincode: v.pincode, categories: exams, created_by: user.id, status: "draft" })
    .select("id")
    .single();
  if (error || !inst) return { ok: false, error: "Could not create your institute. Please try again." };

  const id = inst.id as string;
  const steps = await Promise.all([
    supabase.from("institute_private").insert({ institute_id: id, contact_person: v.contactPerson, contact_email: v.email, contact_phone: v.phone.replace(/^(\+91[\s-]?|0)/, ""), state: v.state }),
    (async () => {
      const f = parseFaculty(v.faculty);
      return f.length ? supabase.from("faculty").insert(f.map((x) => ({ ...x, institute_id: id }))) : { error: null };
    })(),
    (async () => {
      const { data: course, error: ce } = await supabase
        .from("courses")
        .insert({ institute_id: id, name: exams[0] ?? v.name, exam: exams[0] ?? null, tuition_fee_inr: v.tuitionFee, published: false })
        .select("id").single();
      if (ce || !course) return { error: ce };
      return supabase.from("batches").insert({ course_id: course.id, timing: v.batchTimings });
    })(),
  ]);
  if (steps.some((s) => s.error)) return { ok: false, error: "Your institute was created as a draft, but some details failed to save. Open your dashboard to complete them." };

  const { error: submitErr } = await supabase.from("institutes").update({ status: "submitted" }).eq("id", id);
  if (submitErr) return { ok: false, error: "Saved as a draft, but submitting for review failed. Please try again from your dashboard." };

  revalidatePath("/institute", "layout");
  return { ok: true, message: "Submitted for review. Our team will verify your documents before any verified badge is shown.", redirectTo: "/institute/dashboard" };
}

export async function saveCourse(input: unknown): Promise<ActionResult> {
  const parsed = courseSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  const ctx = await context();
  if ("result" in ctx) return ctx.result;
  const { supabase, user } = ctx;
  const instituteId = await myInstituteId(supabase, user.id);
  if (!instituteId) return { ok: false, error: "Complete institute onboarding first." };

  const v = parsed.data;
  const row = {
    institute_id: instituteId, name: v.name, exam: v.exam || null, level: v.level || null, duration_months: v.durationMonths,
    tuition_fee_inr: v.tuitionFeeINR, other_fees_inr: v.otherFeesINR, mode: v.mode, batch_size: v.batchSize,
    syllabus: v.syllabus || null, demo_enabled: v.demoEnabled,
  };
  if (v.id) {
    // Scoped by institute_id as well as RLS, so a forged id for another institute updates nothing.
    const { data, error } = await supabase.from("courses").update(row).eq("id", v.id).eq("institute_id", instituteId).select("id");
    if (error || !data?.length) return { ok: false, error: "Could not update that course." };
  } else {
    const { data, error } = await supabase.from("courses").insert({ ...row, published: false }).select("id").single();
    if (error || !data) return { ok: false, error: "Could not create the course." };
    const { error: be } = await supabase.from("batches").insert({ course_id: data.id, timing: v.timing, seats_total: v.seats ?? null, seats_available: v.seats ?? null });
    if (be) return { ok: false, error: "Course saved, but the batch timing failed to save." };
  }
  revalidatePath("/institute/courses");
  return { ok: true, message: v.id ? "Course updated." : "Course created as unpublished." };
}

export async function setCoursePublished(courseId: string, published: boolean): Promise<ActionResult> {
  if (!/^[0-9a-f-]{36}$/i.test(courseId)) return { ok: false, error: "Invalid course." };
  const ctx = await context();
  if ("result" in ctx) return ctx.result;
  const { supabase, user } = ctx;
  const instituteId = await myInstituteId(supabase, user.id);
  if (!instituteId) return { ok: false, error: "No institute found." };
  const { data, error } = await supabase.from("courses").update({ published }).eq("id", courseId).eq("institute_id", instituteId).select("id");
  if (error || !data?.length) return { ok: false, error: "Could not change publish state." };
  revalidatePath("/institute/courses");
  return { ok: true };
}
