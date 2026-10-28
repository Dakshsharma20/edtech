import { DemoNotice } from "@/components/ui/feedback";
import { DashHeader } from "@/components/dashboard/widgets";
import { LeadPackagePicker } from "@/components/dashboard/lead-package-picker";
import { demoCities, demoExams } from "@/lib/demo/listings";
import { demoLeadPackages } from "@/lib/demo/pricing";

export const metadata = { title: "Lead packages" };

export default function InstituteLeadsPage() {
  return (
    <>
      <DashHeader title="Lead packages" description="Buy consented student enquiries that match your courses and location." />
      <DemoNotice>Package sizes and prices are sample values; admins will configure them.</DemoNotice>
      <LeadPackagePicker packages={demoLeadPackages} cities={demoCities} exams={demoExams} />
    </>
  );
}
