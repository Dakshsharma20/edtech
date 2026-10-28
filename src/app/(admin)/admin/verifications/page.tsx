import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DemoNotice, EmptyState, StatusBanner } from "@/components/ui/feedback";
import { Table, TBody, TD, TH, THead, TR } from "@/components/ui/table";
import { ReviewActions } from "@/components/dashboard/review-actions";
import { DashHeader } from "@/components/dashboard/widgets";
import { createClient } from "@/lib/supabase/server";
import { verificationQueue } from "@/lib/demo/dashboard";
import { formatDate } from "@/lib/utils";
import { BadgeCheck } from "lucide-react";

export const metadata = { title: "Verification" };

export default async function VerificationsPage() {
  const supabase = await createClient();

  if (!supabase) {
    return (
      <>
        <DashHeader title="Institute & tutor verification" description="Review applications and documents before any verified badge is granted." />
        <DemoNotice>Sample queue. Connect Supabase to review real applications.</DemoNotice>
        <Table>
          <THead><TR><TH>ID</TH><TH>Applicant</TH><TH>Type</TH><TH>City</TH><TH>Status</TH><TH>Actions</TH></TR></THead>
          <TBody>
            {verificationQueue.map((v) => (
              <TR key={v.id}><TD>{v.id}</TD><TD className="font-medium text-ink">{v.name}</TD><TD>{v.type}</TD><TD>{v.city}</TD><TD><Badge variant="warning">{v.status}</Badge></TD>
                <TD><Button size="sm" disabled title="Needs Supabase">Approve</Button></TD></TR>
            ))}
          </TBody>
        </Table>
      </>
    );
  }

  // RLS: only an admin session can read other institutes' submitted rows and documents.
  const { data: rows } = await supabase
    .from("institutes")
    .select("id, name, city, status, verification, created_at, institute_verification_documents(count)")
    .eq("status", "submitted")
    .order("created_at");

  return (
    <>
      <DashHeader title="Institute verification" description="Applications waiting for review, oldest first." />
      <StatusBanner title="Every decision is audit-logged">
        Approving publishes the listing and marks it Verified. Document viewing (signed links) is not built yet, so confirm documents out-of-band for now.
      </StatusBanner>
      {!rows?.length ? (
        <EmptyState icon={BadgeCheck} title="Nothing to review" description="New institute applications appear here once submitted." />
      ) : (
        <Table>
          <THead><TR><TH>Institute</TH><TH>City</TH><TH>Submitted</TH><TH>Documents</TH><TH>Actions</TH></TR></THead>
          <TBody>
            {rows.map((r) => (
              <TR key={r.id}>
                <TD className="font-medium text-ink">{r.name}</TD><TD>{r.city ?? "—"}</TD><TD>{formatDate(r.created_at)}</TD>
                <TD>{(r.institute_verification_documents as unknown as { count: number }[])?.[0]?.count ?? 0}</TD>
                <TD><ReviewActions instituteId={r.id} /></TD>
              </TR>
            ))}
          </TBody>
        </Table>
      )}
    </>
  );
}
