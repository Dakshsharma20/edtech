"use server";

import { revalidatePath } from "next/cache";
import { getCurrentUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import type { ActionResult } from "@/lib/validation/auth";

type Decision = "approve" | "reject" | "suspend";

/**
 * Admin decision on an institute application. Authorization is checked here on the server AND by RLS/DB triggers;
 * the audit record is written by a SECURITY DEFINER function that itself re-checks the admin role.
 * "approve" publishes the listing and marks it verified, so the admin must have reviewed the documents first.
 */
export async function decideInstitute(instituteId: string, decision: Decision, note?: string): Promise<ActionResult> {
  if (!/^[0-9a-f-]{36}$/i.test(instituteId) || !["approve", "reject", "suspend"].includes(decision)) return { ok: false, error: "Invalid request." };
  const supabase = await createClient();
  if (!supabase) return { ok: false, preview: true, error: "Supabase is not configured." };
  const user = await getCurrentUser();
  if (!user?.roles.includes("admin")) return { ok: false, error: "Not authorised." };

  const patch =
    decision === "approve" ? { status: "published", verification: "verified" }
    : decision === "reject" ? { status: "rejected", verification: "not_verified" }
    : { status: "suspended" };
  const { data, error } = await supabase.from("institutes").update(patch).eq("id", instituteId).select("id");
  if (error || !data?.length) return { ok: false, error: "Could not update the institute." };

  const { error: auditErr } = await supabase.rpc("log_admin_action", {
    _action: `institute_${decision}`, _target_type: "institute", _target_id: instituteId, _details: { note: note?.slice(0, 500) ?? null },
  });
  // The decision already applied; surface a failed audit write loudly instead of hiding it.
  if (auditErr) return { ok: false, error: "Decision applied, but the audit log write failed. Please report this." };

  revalidatePath("/admin/verifications");
  return { ok: true, message: `Institute ${decision}d.` };
}
