import type { Course, Faculty, Institute, Tutor, VerificationStatus } from "@/types";

/* eslint-disable @typescript-eslint/no-explicit-any */
const verificationNote: Record<VerificationStatus, string> = {
  verified: "Documents reviewed and approved by an administrator.",
  pending_review: "Submitted for review. Not yet verified.",
  not_verified: "Not verified. Details are supplied by the provider.",
};

export function mapInstitute(row: any): Institute {
  const courses: Course[] = (row.courses ?? []).map((c: any) => ({
    id: c.id,
    name: c.name,
    exam: c.exam ?? "",
    level: c.level ?? "",
    durationMonths: c.duration_months ?? 0,
    tuitionFeeINR: c.tuition_fee_inr,
    otherFeesINR: c.other_fees_inr ?? 0,
    mode: c.mode,
    batchTimings: (c.batches ?? []).map((b: any) => b.timing),
    batchSize: c.batch_size ?? 0,
    demoEnabled: !!c.demo_enabled,
  }));
  const faculty: Faculty[] = (row.faculty ?? []).map((f: any) => ({
    id: f.id, name: f.name, qualification: f.qualification ?? "", experienceYears: f.experience_years ?? 0, subjects: f.subjects ?? [],
  }));
  const status: VerificationStatus = row.verification;
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    tagline: row.tagline ?? "",
    city: row.city ?? "",
    locality: row.locality ?? "",
    address: row.address ?? "",
    categories: row.categories ?? [],
    modes: row.modes ?? [],
    languages: row.languages ?? [],
    about: row.about ?? "",
    facilities: row.facilities ?? [],
    refundPolicy: row.refund_policy ?? "Not provided",
    courses,
    faculty,
    faqs: [], // FAQs get their own table in a later stage
    lastUpdated: row.updated_at,
    verification: { status, note: verificationNote[status] },
    rating: null, // reviews arrive in Stage 4; never invented
    demoAvailable: courses.some((c) => c.demoEnabled),
    isDemo: !!row.is_demo,
  };
}

export function mapTutor(row: any): Tutor {
  const status: VerificationStatus = row.verification;
  return {
    id: row.id,
    slug: row.slug,
    name: row.display_name,
    headline: row.headline ?? "",
    city: row.city ?? "",
    serviceLocalities: row.service_localities ?? [],
    subjects: row.subjects ?? [],
    levels: row.levels ?? [],
    modes: [...(row.online ? ["online" as const] : []), ...(row.home ? ["home" as const] : [])],
    languages: row.languages ?? [],
    experienceYears: row.experience_years ?? 0,
    qualifications: row.qualifications ?? [],
    about: row.about ?? "",
    hourlyFeeINR: row.hourly_fee_inr ?? 0,
    monthlyFeeINR: row.monthly_fee_inr ?? 0,
    availability: row.availability ?? [],
    demoAvailable: !!row.demo_available,
    lastUpdated: row.updated_at,
    verification: { status, note: verificationNote[status] },
    rating: null,
    isDemo: !!row.is_demo,
  };
}
