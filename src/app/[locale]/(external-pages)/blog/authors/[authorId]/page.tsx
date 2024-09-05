import { T } from '@/components/ui/Typography';
import {
  anonGetBlogPostsByAuthorId,
  anonGetOneAuthor,
} from '@/data/anon/internalBlog';
import moment from 'moment';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import { z } from 'zod';

const paramsSchema = z.object({
  authorId: z.string(),
});

export default async function BlogPostPage({ params }: { params: unknown }) {
  const { authorId } = paramsSchema.parse(params);

  const author = await anonGetOneAuthor(authorId);
  const blogs = await anonGetBlogPostsByAuthorId(authorId);
  try {
    return (
      <div className="space-y-8 w-full">
        <div className="flex items-center flex-col space-y-4">
          <div className="space-y-3 mb-6 text-center">
            <T.Subtle>Blogs</T.Subtle>
            <T.H1>All {author[0].display_name}'s posts</T.H1>
            <T.P className="text-xl leading-[30px] text-muted-foreground">
              Here is a collection of the latest blog posts
            </T.P>
          </div>
        </div>
        <div className="flex gap-5 flex-col">
          <Suspense fallback={<T.Subtle>Loading authors...</T.Subtle>}>
            <div className="space-y-2 mx-4 sm:mx-8 md:mx-0">
              <div className="mx-auto mt-16 grid max-w-2xl grid-cols-1 gap-x-8 gap-y-20 lg:mx-0 lg:max-w-none lg:grid-cols-3">
                {blogs.map(({ internal_blog_posts }) => (
                  <article
                    key={internal_blog_posts?.id}
                    className="flex max-w-xl flex-col items-start justify-start"
                  >
                    <div className="relative w-full">
                      <img
                        src={
                          internal_blog_posts?.cover_image ??
                          '/images/nextbase-logo.png'
                        }
                        alt={internal_blog_posts?.title}
                        className="aspect-[16/9] w-full rounded-2xl bg-gray-100  object-cover sm:aspect-[2/1] lg:aspect-[3/2]"
                      />
                    </div>
                    <div className="max-w-xl">
                      <div className="mt-5 flex items-center gap-x-4 text-xs">
                        <time
                          dateTime={internal_blog_posts?.created_at}
                          className="text-muted-foreground dark:text-secondary-foreground uppercase"
                        >
                          {moment(internal_blog_posts?.created_at).format(
                            'MMM D, YYYY',
                          )}
                        </time>
                      </div>
                      <div className="group relative">
                        <h3 className="mt-2 text-2xl font-semibold text-foreground dark:text-card-foreground group-hover:text-muted-foreground dark:group-hover:text-secondary-foreground">
                          <a href={`/blog/${internal_blog_posts?.slug}`}>
                            <span className="absolute inset-0" />
                            {internal_blog_posts?.title}
                          </a>
                        </h3>
                        <p className="mt-2 line-clamp-3 text-base text-muted-foreground dark:text-muted-foreground">
                          {internal_blog_posts?.summary}
                        </p>
                      </div>
                    </div>
                  </article>
                ))}
              </div>
            </div>
          </Suspense>
        </div>
      </div>
    );
  } catch (error) {
    return notFound();
  }
}
