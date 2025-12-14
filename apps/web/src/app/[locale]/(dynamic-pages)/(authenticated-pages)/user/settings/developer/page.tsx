import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { Skeleton } from "@/components/ui/skeleton";
import { T } from "@/components/ui/typography-ui";
import { getActiveDeveloperKeyCount } from "@/data/user/unkey";
import { ActiveApiKeyList } from "./active-api-key-list";
import { GenerateApiKey } from "./generate-api-key";
import { RevokedApiKeyList } from "./revoked-api-key-list";

async function DeveloperSettingsContent() {
  const activeDeveloperKeyCount = await getActiveDeveloperKeyCount();
  return (
    <>
      <div className="space-y-2">
        <Suspense fallback={<Skeleton className="h-6 w-16" />}>
          <ActiveApiKeyList />
        </Suspense>
        {activeDeveloperKeyCount < 3 ? (
          <GenerateApiKey key={activeDeveloperKeyCount} />
        ) : (
          <T.Subtle>You have reached API Key Limit.</T.Subtle>
        )}
      </div>
      <Suspense fallback={<Skeleton className="h-6 w-16" />}>
        <RevokedApiKeyList />
      </Suspense>
    </>
  );
}

export default async function DeveloperSettingsPage() {
  return (
    <div className="space-y-8">
      <PageHeading
        subTitle="Manage your developer settings here."
        subTitleClassName="text-base -mt-1"
        title="Developer Settings"
        titleClassName="text-xl"
      />
      <Suspense>
        <DeveloperSettingsContent />
      </Suspense>
    </div>
  );
}
