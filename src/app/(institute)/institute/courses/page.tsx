import { StatusBanner } from "@/components/ui/feedback";
import { CourseManager, type CourseRow } from "@/components/dashboard/course-manager";
import { DashHeader } from "@/components/dashboard/widgets";
import { getCurrentUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export const metadata = { title: "Courses and batches" };

export default async function InstituteCoursesPage() {
  const supabase = await createClient();
  const user = supabase ? await getCurrentUser() : null;
  let courses: CourseRow[] = [];
  let hasInstitute = false;

  if (supabase && user) {
    const { data: member } = await supabase.from("institute_members").select("institute_id").eq("user_id", user.id).limit(1).maybeSingle();
    if (member) {
      hasInstitute = true;
      // RLS scopes this to the member's own institute even without the explicit filter.
      const { data } = await supabase.from("courses").select("*, batches(timing)").eq("institute_id", member.institute_id).order("created_at");
      courses = (data ?? []).map((c) => ({
        id: c.id, name: c.name, exam: c.exam, durationMonths: c.duration_months, tuitionFeeINR: c.tuition_fee_inr,
        otherFeesINR: c.other_fees_inr, mode: c.mode, published: c.published, timings: (c.batches ?? []).map((b: { timing: string }) => b.timing),
      }));
    }
  }

  return (
    <>
      <DashHeader title="Courses and batches" description="Create courses, set fees and timings, and publish when ready." />
      {!supabase && <StatusBanner tone="warning" title="Backend not connected">Supabase is not configured, so courses cannot be loaded or saved yet.</StatusBanner>}
      {supabase && !hasInstitute && <StatusBanner tone="warning" title="Complete onboarding first">Submit your institute application before adding courses.</StatusBanner>}
      <CourseManager courses={courses} canEdit={!!supabase && hasInstitute} />
    </>
  );
}
