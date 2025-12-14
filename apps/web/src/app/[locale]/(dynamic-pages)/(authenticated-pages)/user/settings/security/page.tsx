import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { serverGetLoggedInUserVerified } from "@/utils/server/server-get-logged-in-user";
import { UpdateEmail } from "./update-email";
import { UpdatePassword } from "./update-password";

async function SecuritySettingsContent() {
  // sensitive operation.
  // recheck user (instead of only checking the claims)
  const user = await serverGetLoggedInUserVerified();
  return (
    <div className="max-w-sm space-y-8">
      <PageHeading
        subTitle="Manage your login credentials here."
        subTitleClassName="text-base -mt-1"
        title="Security Settings"
        titleClassName="text-xl"
      />
      <div className="space-y-24">
        <UpdateEmail initialEmail={user.email} />
        <UpdatePassword />
      </div>
    </div>
  );
}

export default async function SecuritySettingsPage() {
  return (
    <Suspense>
      <SecuritySettingsContent />
    </Suspense>
  );
}
