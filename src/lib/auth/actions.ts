"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { siteConfig } from "@/lib/config";
import { rateLimit } from "@/lib/rate-limit";
import { createClient } from "@/lib/supabase/server";
import { forgotSchema, loginSchema, registerSchema, resetSchema, type ActionResult } from "@/lib/validation/auth";
import { getCurrentUser, portalHome, safeNext } from "./session";

const PREVIEW: ActionResult = {
  ok: false,
  preview: true,
  error: "Supabase is not configured, so nothing was sent. Add the Supabase env vars to enable real sign-in.",
};

async function clientKey(action: string) {
  const h = await headers();
  const ip = h.get("x-forwarded-for")?.split(",")[0]?.trim() || "unknown";
  return `${action}:${ip}`;
}

export async function signIn(input: unknown, next?: string | null): Promise<ActionResult> {
  const parsed = loginSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  if (!rateLimit(await clientKey("login"), 8, 60_000)) return { ok: false, error: "Too many attempts. Please wait a minute and try again." };

  const supabase = await createClient();
  if (!supabase) return PREVIEW;

  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  // One generic message: never reveal whether the email exists.
  if (error) return { ok: false, error: "Invalid email or password." };

  const user = await getCurrentUser();
  return { ok: true, redirectTo: safeNext(next) ?? portalHome(user?.roles ?? []) };
}

export async function signUp(input: unknown): Promise<ActionResult> {
  const parsed = registerSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  if (!rateLimit(await clientKey("register"), 5, 10 * 60_000)) return { ok: false, error: "Too many sign-up attempts. Please try again later." };

  const supabase = await createClient();
  if (!supabase) return PREVIEW;

  const { name, email, phone, password, role } = parsed.data;
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      emailRedirectTo: `${siteConfig.url}/auth/callback?next=/login`,
      // The DB trigger reads these. It only honours student/institute/tutor, never admin.
      data: { full_name: name, phone, role },
    },
  });
  if (error) return { ok: false, error: "We could not create that account. If you already registered, try logging in." };

  // With email confirmation enabled there is no session yet.
  if (!data.session) return { ok: true, message: "Check your email to confirm your address, then log in." };
  return { ok: true, redirectTo: role === "student" ? "/student/dashboard" : "/onboarding" };
}

export async function requestPasswordReset(input: unknown): Promise<ActionResult> {
  const parsed = forgotSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  if (!rateLimit(await clientKey("reset"), 3, 10 * 60_000)) return { ok: false, error: "Too many requests. Please try again later." };

  const supabase = await createClient();
  if (!supabase) return PREVIEW;

  await supabase.auth.resetPasswordForEmail(parsed.data.email, { redirectTo: `${siteConfig.url}/auth/callback?next=/reset-password` });
  // Same response whether or not the account exists.
  return { ok: true, message: "If an account exists for that email, a reset link is on its way." };
}

export async function updatePassword(input: unknown): Promise<ActionResult> {
  const parsed = resetSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Invalid input" };
  const supabase = await createClient();
  if (!supabase) return PREVIEW;
  // Requires the recovery session established by /auth/callback.
  const { data } = await supabase.auth.getUser();
  if (!data.user) return { ok: false, error: "This reset link has expired. Request a new one." };
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return { ok: false, error: "Could not update your password. Try a different one." };
  return { ok: true, message: "Password updated.", redirectTo: "/login" };
}

export async function signOut() {
  const supabase = await createClient();
  if (supabase) await supabase.auth.signOut();
  redirect("/login");
}
