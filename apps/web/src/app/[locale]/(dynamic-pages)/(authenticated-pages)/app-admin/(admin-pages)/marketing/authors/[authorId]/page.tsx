// src/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/authors/[authorId]/page.tsx

import { notFound } from "next/navigation";
import { Suspense } from "react";
import { getAuthorProfileById } from "@/data/admin/marketing-authors";
import { UpdateMarketingAuthorProfileForm } from "./update-marketing-author-profile-form";

async function UpdateMarketingAuthorPageContent(props: {
  params: Promise<{ authorId: string }>;
}) {
  const params = await props.params;
  const author = await getAuthorProfileById(params.authorId);

  if (!author) {
    notFound();
  }

  return (
    <div className="space-y-6">
      <h1 className="font-bold text-3xl">Update Marketing Author Profile</h1>
      <UpdateMarketingAuthorProfileForm author={author} />
    </div>
  );
}

export default async function UpdateMarketingAuthorPage(props: {
  params: Promise<{ authorId: string }>;
}) {
  return (
    <Suspense>
      <UpdateMarketingAuthorPageContent params={props.params} />
    </Suspense>
  );
}
