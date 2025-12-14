// @/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/[postId]/page.tsx

import { notFound } from "next/navigation";
import { Suspense } from "react";
import { getAllAuthorProfiles } from "@/data/admin/marketing-authors";
import { getBlogPostById } from "@/data/admin/marketing-blog";
import { getAllMarketingTags } from "@/data/admin/marketing-tags";
import { EditBlogPostLayout } from "./edit-blog-post-layout";

async function EditBlogPostPageContent(props: {
  params: Promise<{ postId: string }>;
}) {
  const params = await props.params;
  const post = await getBlogPostById(params.postId);

  if (!post) {
    notFound();
  }

  const authors = await getAllAuthorProfiles();
  const tags = await getAllMarketingTags();

  return (
    <div className="space-y-6">
      <EditBlogPostLayout authors={authors} post={post} tags={tags} />
    </div>
  );
}

export default async function EditBlogPostPage(props: {
  params: Promise<{ postId: string }>;
}) {
  return (
    <Suspense>
      <EditBlogPostPageContent params={props.params} />
    </Suspense>
  );
}
