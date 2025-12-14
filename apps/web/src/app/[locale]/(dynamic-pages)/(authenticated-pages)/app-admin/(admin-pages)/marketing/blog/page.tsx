// src/app/[locale]/(dynamic-pages)/(authenticated-pages)/app-admin/(admin-pages)/marketing/blog/page.tsx
import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";
import { cachedGetAllBlogPosts } from "@/data/admin/marketing-blog";
import { BlogList } from "./blog-list";
import { DeleteBlogPostProvider } from "./delete-blog-post-provider";

async function MarketingBlogPageContent() {
  const posts = await cachedGetAllBlogPosts();
  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Typography.H1 className="font-bold text-3xl tracking-tight">
          Marketing Blog Posts
        </Typography.H1>
        <Typography.P className="text-muted-foreground">
          Manage and view all marketing blog posts.
        </Typography.P>
      </div>
      <BlogList posts={posts} />
    </div>
  );
}

export default async function MarketingBlogPage() {
  return (
    <Suspense>
      <DeleteBlogPostProvider>
        <MarketingBlogPageContent />
      </DeleteBlogPostProvider>
    </Suspense>
  );
}
