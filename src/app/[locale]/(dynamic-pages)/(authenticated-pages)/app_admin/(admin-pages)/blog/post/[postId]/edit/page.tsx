import Overline from "@/components/Text/Overline";
import { T } from "@/components/ui/Typography";
import { Skeleton } from "@/components/ui/skeleton";
import {
  getAllAuthors,
  getAllBlogTags,
  getBlogPostById,
  getBlogTagRelationships,
} from "@/data/admin/internal-blog";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";
import { BlogForm, type EditBlogFormProps } from "../../../BlogForm";
import { ChevronLeft } from "lucide-react";

const paramsSchema = z.object({
  postId: z.string(),
});

async function BlogFormWrapper({ postId }: { postId: string }) {
  const [post, authors, tags, blogTagRelationships] = await Promise.all([
    getBlogPostById(postId),
    getAllAuthors(),
    getAllBlogTags(),
    getBlogTagRelationships(postId),
  ]);

  let postAuthorId: string | undefined = undefined;
  const authorBlogPosts = Array.isArray(post.internal_blog_author_posts)
    ? post.internal_blog_author_posts[0]
    : post.internal_blog_author_posts;
  if (!authorBlogPosts) {
    console.log("Linked author not found");
  } else {
    postAuthorId = authorBlogPosts?.author_id ?? undefined;
  }

  const initialBlogPost: EditBlogFormProps['initialBlogPost'] = {
    author_id: postAuthorId,
    content: post.content,
    cover_image: post.cover_image ?? undefined,
    is_featured: post.is_featured,
    slug: post.slug,
    summary: post.summary,
    title: post.title,
    status: post.status,
    json_content:
      typeof post.json_content === 'string'
        ? JSON.parse(post.json_content)
        : typeof post.json_content === 'object' && post.json_content !== null
          ? post.json_content
          : {},
    tags: tags,
  };

  return (
    <BlogForm
      tags={tags}
      authors={authors}
      mode="update"
      initialBlogPost={initialBlogPost}
      postId={post.id}
    />
  );
}

export default async function CreateBlogPostPage({
  params,
}: {
  params: unknown;
}) {
  try {
    const { postId } = paramsSchema.parse(params);

    return (
      <div className="space-y-4">
        <Link href="/app_admin/blog">
          <div className="flex items-center space-x-2 group">
            <ChevronLeft className="group-hover:text-gray-800 group-hover:dark:text-gray-400 relative w-4 h-4 text-gray-500 dark:text-gray-600 hover:-translate-x-10" />
            <Overline className="group-hover:text-gray-800 group-hover:dark:text-gray-400 text-gray-500 dark:text-gray-600">
              Back to blog
            </Overline>
          </div>
        </Link>
        <T.H3>Edit Blog Post</T.H3>
        <Suspense fallback={<Skeleton className="w-16 h-6" />}>
          <BlogFormWrapper postId={postId} />
        </Suspense>
      </div>
    );
  } catch (error) {
    console.log(error);
    return notFound();
  }
}
