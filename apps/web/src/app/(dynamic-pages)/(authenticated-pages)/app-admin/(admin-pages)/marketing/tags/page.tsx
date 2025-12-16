import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";
import { getAllMarketingTags } from "@/data/admin/marketing-tags";
import { CreateTagButton } from "./create-tag-button";
import { DeleteTagProvider } from "./delete-tag-provider";
import { TagsList } from "./tags-list";

async function MarketingTagsPageContent() {
  const tags = await getAllMarketingTags();
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <Typography.H1 className="font-bold text-3xl tracking-tight">
          Marketing Tags
        </Typography.H1>
        <CreateTagButton />
      </div>
      <Typography.P className="text-muted-foreground">
        Manage and view all marketing tags.
      </Typography.P>
      <TagsList tags={tags} />
    </div>
  );
}

export default async function MarketingTagsPage() {
  return (
    <Suspense>
      <DeleteTagProvider>
        <MarketingTagsPageContent />
      </DeleteTagProvider>
    </Suspense>
  );
}
