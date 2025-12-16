import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";
import { cachedGetAllChangelogs } from "@/data/admin/marketing-changelog";
import { ChangelogList } from "./changelog-list";
import { CreateChangelogButton } from "./create-changelog-button";
import { DeleteChangelogProvider } from "./delete-changelog-provider";

async function MarketingChangelogPageContent() {
  const changelogs = await cachedGetAllChangelogs();
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <Typography.H1 className="font-bold text-3xl tracking-tight">
          Marketing Changelogs
        </Typography.H1>
        <CreateChangelogButton />
      </div>
      <Typography.P className="text-muted-foreground">
        Manage and view all marketing changelogs.
      </Typography.P>
      <ChangelogList changelogs={changelogs} />
    </div>
  );
}

export default async function MarketingChangelogPage() {
  return (
    <Suspense>
      <DeleteChangelogProvider>
        <MarketingChangelogPageContent />
      </DeleteChangelogProvider>
    </Suspense>
  );
}
