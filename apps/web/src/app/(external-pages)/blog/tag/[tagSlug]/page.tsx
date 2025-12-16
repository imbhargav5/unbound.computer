import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";
import { T } from "@/components/ui/typography-ui";
import {
  cachedGetAllBlogTags,
  cachedGetPublishedBlogPostsByTagSlug,
  cachedGetTagBySlug,
} from "@/data/anon/marketing-blog";
import { PublicBlogList } from "../../public-blog-list";
import { TagsNav } from "../../tags-nav";

const BlogListByTagPageParamsSchema = z.object({
  tagSlug: z.string(),
});

export async function generateStaticParams() {
  const tags = await cachedGetAllBlogTags();
  return tags.map((tag) => ({ tagSlug: tag.slug }));
}

export async function generateMetadata(props: {
  params: Promise<unknown>;
}): Promise<Metadata> {
  const params = await props.params;
  const { tagSlug } = BlogListByTagPageParamsSchema.parse(params);
  const tag = await cachedGetTagBySlug(tagSlug);

  if (!tag) {
    return {
      title: "Blog | Nextbase Ultimate",
      description: "Explore the latest updates from the Nextbase team.",
    } satisfies Metadata;
  }

  return {
    title: `${tag.name} | Blog | Nextbase Ultimate`,
    description: tag.description,
  };
}

async function Tags() {
  const tags = await cachedGetAllBlogTags();
  return <TagsNav tags={tags} />;
}

async function BlogList({ tagSlug }: { tagSlug: string }) {
  const blogPosts = await cachedGetPublishedBlogPostsByTagSlug(tagSlug);
  return <PublicBlogList blogPosts={blogPosts} />;
}

async function Tag({ params }: { params: Promise<unknown> }) {
  const { tagSlug } = BlogListByTagPageParamsSchema.parse(await params);
  const tag = await cachedGetTagBySlug(tagSlug);

  if (!tag) {
    notFound();
  }

  return (
    <div className="w-full space-y-8">
      <div className="flex flex-col items-center space-y-4">
        <div className="space-y-3 text-center">
          <T.Subtle>Blog</T.Subtle>
          <T.H1>{tag.name}</T.H1>
          <T.Subtle>{tag.description}</T.Subtle>
        </div>
        <Suspense>
          {" "}
          <Tags />{" "}
        </Suspense>
      </div>
      <Suspense>
        {" "}
        <BlogList tagSlug={tagSlug} />{" "}
      </Suspense>
    </div>
  );
}

export default async function BlogListByTagPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <Tag params={props.params} />
    </Suspense>
  );
}
