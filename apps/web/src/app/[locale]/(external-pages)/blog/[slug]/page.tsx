import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Suspense } from "react";
import { z } from "zod";
import { Link } from "@/components/intl-link";
import { TiptapJSONContentToHTML } from "@/components/tiptap-json-content-to-html";
import { Badge } from "@/components/ui/badge";
import { T } from "@/components/ui/typography-ui";
import {
  cachedGetPublishedBlogPostBySlug,
  cachedGetPublishedBlogPosts,
} from "@/data/anon/marketing-blog";
import { routing } from "@/i18n/routing";
import AuthorCard from "../author-card";
import { BlogPostMedia } from "./blog-post-media";

const paramsSchema = z.object({
  slug: z.string(),
  locale: z.string(),
});

const isDev = process.env.NODE_ENV !== "production";

type BlogPosts = Awaited<ReturnType<typeof cachedGetPublishedBlogPosts>>;
type BlogPost = BlogPosts extends Array<infer Item> ? Item : never;
type PublishedBlogPost = Awaited<
  ReturnType<typeof cachedGetPublishedBlogPostBySlug>
>;

export async function generateMetadata(props: {
  params: Promise<unknown>;
}): Promise<Metadata> {
  const params = await props.params;
  // read route params
  const { slug } = paramsSchema.parse(params);
  const post = await cachedGetPublishedBlogPostBySlug(slug);

  if (!post) {
    return {
      title: "Blog | Nextbase Boilerplate",
      description: "Discover the latest updates from the Nextbase team.",
    } satisfies Metadata;
  }
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

async function BlogPost({ params }: { params: Promise<unknown> }) {
  "use cache: remote";
  const { slug, locale } = paramsSchema.parse(await params);
  setRequestLocale(locale);
  const post = await cachedGetPublishedBlogPostBySlug(slug);

  if (!post) {
    return notFound();
  }

  const tags = post.marketing_blog_post_tags_relationship?.map(
    (tag) => tag.marketing_tags
  );
  const validTags = tags.filter((tag) => tag !== null);
  const mediaType =
    (post.media_type as "image" | "video" | "gif" | null) || "image";

  return (
    <div className="relative mx-auto w-full max-w-4xl space-y-8 px-4 md:px-0">
      {post.cover_image ? (
        <BlogPostMedia
          alt={post.title}
          posterUrl={post.media_poster}
          type={mediaType}
          url={post.cover_image}
        />
      ) : null}
      <div className="wyiswyg wysiwyg-lg dark:wysiwyg-invert max-w-full font-default wysiwyg-headings:font-display focus:outline-hidden">
        <h1>{post.title}</h1>
        <TiptapJSONContentToHTML jsonContent={post.json_content} />
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
}

// Return a list of `params` to populate the [slug] dynamic segment
export async function generateStaticParams() {
  const posts = await cachedGetPublishedBlogPosts();

  return routing.locales.map((locale) =>
    posts.map((post) => ({
      slug: post.slug,
      locale,
    }))
  );
}

export default async function BlogPostPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense fallback={<T.Subtle>Loading blog post...</T.Subtle>}>
      <BlogPost params={props.params} />
    </Suspense>
  );
}
