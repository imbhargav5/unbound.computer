import moment from "moment";
import { setRequestLocale } from "next-intl/server";
import { Suspense } from "react";
import { z } from "zod";
import { T } from "@/components/ui/typography-ui";
import {
  cachedGetAllAuthors,
  cachedGetBlogPostsByAuthorId,
  cachedGetOneAuthorBySlug,
} from "@/data/anon/marketing-blog";
import { routing } from "@/i18n/routing";
import AuthorCard from "../../author-card";

const paramsSchema = z.object({
  authorSlug: z.string(),
  locale: z.string(),
});

export async function generateStaticParams() {
  const authors = await cachedGetAllAuthors();
  return routing.locales.map((locale) =>
    authors.map((author) => ({
      authorSlug: author.slug,
      locale,
    }))
  );
}

async function Author({ params }: { params: Promise<unknown> }) {
  "use cache: remote";
  const { authorSlug, locale } = paramsSchema.parse(await params);
  setRequestLocale(locale);

  const author = await cachedGetOneAuthorBySlug(authorSlug);
  const blogs = await cachedGetBlogPostsByAuthorId(author.id);
  const posts = blogs.map(({ marketing_blog_posts }) => marketing_blog_posts);
  const validPosts = posts.filter((post) => post !== null);
  return (
    <div className="w-full space-y-8">
      <div className="flex flex-col items-center space-y-4">
        <T.H1>{author.display_name}&apos;s profile</T.H1>
        <AuthorCard author={author} trimSummary={false} />
      </div>
      <div className="flex flex-col items-center space-y-4">
        <div className="mb-6 space-y-3 text-center">
          <T.P className="text-muted-foreground text-xl leading-[30px]">
            Here is a collection of latest blog posts by {author.display_name}
          </T.P>
        </div>
      </div>
      <div className="flex flex-col gap-5">
        <div className="mx-4 space-y-2 sm:mx-8 md:mx-0">
          <div className="mx-auto grid max-w-2xl grid-cols-1 gap-x-8 gap-y-20 lg:mx-0 lg:max-w-none lg:grid-cols-3">
            {validPosts.map((post) => (
              <article
                className="flex max-w-xl flex-col items-start justify-start"
                key={post.id}
              >
                <div className="relative w-full">
                  <img
                    alt={post.title}
                    className="aspect-16/9 w-full rounded-2xl bg-gray-100 object-cover sm:aspect-2/1 lg:aspect-3/2"
                    src={post.cover_image ?? "/images/nextbase-logo.png"}
                  />
                </div>
                <div className="max-w-xl">
                  <div className="mt-5 flex items-center gap-x-4 text-xs">
                    <time
                      className="text-muted-foreground uppercase dark:text-secondary-foreground"
                      dateTime={post.created_at}
                    >
                      {moment(post.created_at).format("MMM D, YYYY")}
                    </time>
                  </div>
                  <div className="group relative">
                    <h3 className="mt-2 font-semibold text-2xl text-foreground group-hover:text-muted-foreground dark:text-card-foreground dark:group-hover:text-secondary-foreground">
                      <a href={`/blog/${post.slug}`}>
                        <span className="absolute inset-0" />
                        {post.title}
                      </a>
                    </h3>
                    <p className="mt-2 line-clamp-3 text-base text-muted-foreground dark:text-muted-foreground">
                      {post.summary}
                    </p>
                  </div>
                </div>
              </article>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

export default async function AuthorPage(props: { params: Promise<unknown> }) {
  return (
    <Suspense>
      <Author params={props.params} />
    </Suspense>
  );
}
