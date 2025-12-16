// src/app/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/authors/page.tsx
import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";
import { getAllAuthorProfiles } from "@/data/admin/marketing-authors";
import { AuthorsList } from "./authors-list";
import { DeleteAuthorProvider } from "./delete-author-provider";

async function MarketingAuthorsPageContent() {
  const authors = await getAllAuthorProfiles();
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Typography.H1 className="font-bold text-3xl tracking-tight">
          Marketing Authors
        </Typography.H1>
        <Typography.P className="text-muted-foreground">
          Manage and view all marketing author profiles.
        </Typography.P>
      </div>
      <AuthorsList authors={authors} />
    </div>
  );
}

export default async function MarketingAuthorsPage() {
  return (
    <Suspense>
      <DeleteAuthorProvider>
        <MarketingAuthorsPageContent />
      </DeleteAuthorProvider>
    </Suspense>
  );
}
