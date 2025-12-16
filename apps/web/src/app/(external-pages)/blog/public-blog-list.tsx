import { CalendarDays } from "lucide-react";
import moment from "moment";
import { connection } from "next/server";
import { Fragment, Suspense } from "react";
import { Link } from "@/components/intl-link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { T } from "@/components/ui/typography-ui";
import { anonGetMarketingAuthorById } from "@/data/anon/marketing-authors";
import type { DBTable } from "@/types";
import type { ChangelogMediaType } from "@/utils/changelog";
import { AuthorProfileImage } from "./author-profile-image";
import { BlogPostImage } from "./blog-post-image";

function AuthorProfileSkeleton() {
  return (
    <div className="flex items-center gap-2">
      <Skeleton className="h-8 w-8 rounded-full" />
      <Skeleton className="h-4 w-24" />
    </div>
  );
}

async function AuthorProfile({ authorId }: { authorId: string }) {
  if (!authorId) return null;

  const author = await anonGetMarketingAuthorById(authorId);

  return (
    <div className="flex items-center text-muted-foreground text-sm">
      <AuthorProfileImage
        avatarUrl={author.avatar_url}
        name={author.display_name}
      />
      <div className="relative ml-2 h-4">
        <div className="absolute inset-0 animate-pulse rounded bg-gray-100" />
        <span>{author.display_name}</span>
      </div>
    </div>
  );
}

async function BlogCreatedAt({ createdAt }: { createdAt: string }) {
  await connection();
  return (
    <div className="flex items-center text-muted-foreground text-sm">
      <CalendarDays className="mr-2 h-4 w-4" />
      <span>{moment(createdAt).format("MMM D, YYYY")}</span>
    </div>
  );
}

export function PublicBlogList({
  blogPosts,
}: {
  blogPosts: Array<
    DBTable<"marketing_blog_posts"> & {
      marketing_blog_author_posts: Array<
        DBTable<"marketing_blog_author_posts">
      >;
    }
  >;
}) {
  return (
    <Fragment>
      {blogPosts.length ? (
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 2xl:grid-cols-5">
          {blogPosts.map((post) => {
            const authorId = post.marketing_blog_author_posts[0]?.author_id;
            const mediaType = post.media_type as ChangelogMediaType | null;
            const blogPostImage =
              mediaType === "video" ? post.media_poster : post.cover_image;
            return (
              <Link
                className="transition-opacity hover:opacity-80"
                href={`/blog/${post.slug}`}
                key={post.id}
              >
                <Card className="h-full">
                  <div className="relative aspect-video overflow-hidden rounded-t-lg">
                    <BlogPostImage
                      alt={post.title}
                      src={blogPostImage ?? "/images/nextbase-logo.png"}
                    />
                  </div>
                  <CardHeader className="space-y-2">
                    <CardTitle className="line-clamp-2 font-medium text-lg">
                      {post.title}
                    </CardTitle>
                    <p className="line-clamp-1 text-muted-foreground text-sm">
                      {post.summary}
                    </p>
                  </CardHeader>
                  <CardContent>
                    <Suspense>
                      <BlogCreatedAt createdAt={post.created_at} />
                    </Suspense>
                  </CardContent>
                </Card>
              </Link>
            );
          })}
        </div>
      ) : (
        <T.Subtle className="text-center">No blog posts yet.</T.Subtle>
      )}
    </Fragment>
  );
}
