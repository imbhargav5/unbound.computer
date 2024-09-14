import {
  anonGetPublishedBlogPostBySlug,
  anonGetPublishedBlogPosts,
} from "@/data/anon/marketing-blog";

import { Badge } from "@/components/ui/badge";
import { T } from "@/components/ui/Typography";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { z } from "zod";
import AuthorCard from "../AuthorCard";
import { BlogContentWrapper } from "./BlogContentWrapper";

const paramsSchema = z.object({
  slug: z.string(),
});

// Return a list of `params` to populate the [slug] dynamic segment
export async function generateStaticParams() {
  const posts = await anonGetPublishedBlogPosts();

  return posts.map((post) => ({
    slug: post.slug,
  }));
}

export async function generateMetadata({
  params,
}: {
  params: unknown;
}): Promise<Metadata> {
  // read route params
  const { slug } = paramsSchema.parse(params);
  const post = await anonGetPublishedBlogPostBySlug(slug);
  return {
    title: `${post.title} | Blog | Nextbase Boilerplate`,
    description: post.summary,
    openGraph: {
      title: `${post.title} | Blog | Nextbase Boilerplate`,
      description: post.summary,
      type: "website",
      images: post.cover_image ? [post.cover_image] : undefined,
    },
    twitter: {
      images: post.cover_image ? [post.cover_image] : undefined,
      title: `${post.title} | Blog | Nextbase Boilerplate`,
      card: "summary_large_image",
      site: "@usenextbase",
      description: post.summary,
    },
  };
}
export default async function BlogPostPage({ params }: { params: unknown }) {
  try {
    const { slug } = paramsSchema.parse(params);
    const post = await anonGetPublishedBlogPostBySlug(slug);
    const tags = post?.marketing_blog_post_tags_relationship.map((tag) => tag.marketing_tags);
    const validTags = tags.filter((tag) => tag !== null);
    return (
      <div className="relative w-full space-y-8 px-4 md:px-0 max-w-4xl mx-auto">
        {post.cover_image ? (
          <img
            src={post.cover_image}
            alt={post.title}
            className="aspect-[16/9] w-full rounded-2xl bg-gray-100 object-cover sm:aspect-[2/1] lg:aspect-[3/2]"
          />
        ) : null}
        <div className="prose prose-lg dark:prose-invert prose-headings:font-display font-default focus:outline-none max-w-full">
          <h1>{post.title}</h1>
          <BlogContentWrapper jsonContent={post.json_content} />
        </div>
        {post?.marketing_blog_author_posts[0]?.marketing_author_profiles ? (
          <>
            <T.H4 className="pb-4">Author</T.H4>
            <AuthorCard
              author={
                post.marketing_blog_author_posts[0].marketing_author_profiles
              }
            />
          </>
        ) : null}
        {validTags.length > 0 ? (
          <>
            <T.H4 className="pb-4">Tags</T.H4>
            {validTags.map((tag) => (
              <Link href={`/blog/tag/${tag.slug}`} key={tag.id}>
                <Badge>{tag.name}</Badge>
              </Link>
            ))}
          </>
        ) : null}
      </div>
    );
  } catch (error) {
    return notFound();
  }
}
