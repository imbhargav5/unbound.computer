import { setRequestLocale } from "next-intl/server";
import { Suspense } from "react";
import { T } from "@/components/ui/typography-ui";
import {
  cachedGetAllBlogTags,
  cachedGetPublishedBlogPosts,
} from "@/data/anon/marketing-blog";
import { PublicBlogList } from "../public-blog-list";
import { TagsNav } from "../tags-nav";

export const metadata = {
  title: "Blog List | Nextbase",
  description: "Collection of the latest blog posts from the team at Nextbase",
  icons: {
    icon: "/images/logo-black-main.ico",
  },
};

async function Tags() {
  const tags = await cachedGetAllBlogTags();
  return <TagsNav tags={tags} />;
}

async function BlogList() {
  const blogPosts = await cachedGetPublishedBlogPosts();
  return <PublicBlogList blogPosts={blogPosts} />;
}

async function BlogListContent(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const { locale } = params;

  setRequestLocale(locale);
  return (
    <div className="w-full space-y-8">
      <div className="flex flex-col items-center space-y-4">
        <div className="space-y-2 text-center">
          <T.Subtle>Blog</T.Subtle>
          <T.H1>All blog posts</T.H1>
          <T.P className="text-muted-foreground text-xl leading-[30px]">
            Here is a collection of the latest blog posts from the team at
            Nextbase.
          </T.P>
        </div>
        <Suspense>
          {" "}
          <Tags />{" "}
        </Suspense>
      </div>
      <Suspense>
        {" "}
        <BlogList />{" "}
      </Suspense>
    </div>
  );
}

export default async function BlogListPage(props: {
  params: Promise<{ locale: string }>;
}) {
  return (
    <Suspense>
      <BlogListContent params={props.params} />
    </Suspense>
  );
}
