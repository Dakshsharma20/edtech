import "server-only";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/env";
import type { Portal } from "@/lib/nav";

export type AppRole = "student" | "institute" | "tutor" | "admin";

export interface CurrentUser {
  id: string;
  email: string | null;
  roles: AppRole[];
}

/**
 * Validates the JWT with Supabase (getUser, not getSession) and loads roles from user_roles.
 * Roles are read through RLS: a user can only ever read their own rows.
 */
export async function getCurrentUser(): Promise<CurrentUser | null> {
  const supabase = await createClient();
  if (!supabase) return null;
  const { data } = await supabase.auth.getUser();
  if (!data.user) return null;
  const { data: rows } = await supabase.from("user_roles").select("role").eq("user_id", data.user.id);
  return { id: data.user.id, email: data.user.email ?? null, roles: (rows ?? []).map((r) => r.role as AppRole) };
}

/** Preview (unauthenticated) portals are allowed in development, or when explicitly enabled. Never silently in production. */
export function previewModeAllowed() {
  return process.env.NODE_ENV !== "production" || process.env.EDUMATCH_PREVIEW_MODE === "true";
}

export function portalHome(roles: AppRole[]): string {
  if (roles.includes("admin")) return "/admin/dashboard";
  if (roles.includes("institute")) return "/institute/dashboard";
  if (roles.includes("tutor")) return "/tutor/dashboard";
  if (roles.includes("student")) return "/student/dashboard";
  return "/";
}

/** Only same-site relative paths are accepted for post-login redirects (prevents open redirects). */
export function safeNext(next: string | null | undefined): string | null {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.includes("\\")) return null;
  return next;
}

/**
 * Server-side authorization for a portal. Called from each portal layout.
 * - Not configured + preview allowed: render the demo preview.
 * - Not configured + production: refuse (never fail open).
 * - Configured: must be signed in AND hold exactly the portal's role. Admin does not imply other portals.
 */
export async function requireRole(portal: Portal): Promise<{ preview: boolean; user: CurrentUser | null }> {
  // Authorization must be decided per request, never frozen into a prerendered page at build time.
  await connection();
  if (!isSupabaseConfigured()) {
    if (previewModeAllowed()) return { preview: true, user: null };
    notFound();
  }
  const user = await getCurrentUser();
  if (!user) redirect(`/login?next=/${portal}/dashboard`);
  if (!user.roles.includes(portal)) redirect(portalHome(user.roles));
  return { preview: false, user };
}
