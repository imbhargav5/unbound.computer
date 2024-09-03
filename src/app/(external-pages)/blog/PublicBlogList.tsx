import { T } from '@/components/ui/Typography';
import { DBTable } from '@/types';
import moment from 'moment';

export function PublicBlogList({
  blogPosts,
}: {
  blogPosts: Array<DBTable<'internal_blog_posts'>>;
}) {
  return (
    <>
      {blogPosts.length ? (
        <div className="space-y-2 mx-4 sm:mx-8 md:mx-0">
          <div className="mx-auto mt-16 grid max-w-2xl grid-cols-1 gap-x-8 gap-y-20 lg:mx-0 lg:max-w-none lg:grid-cols-3">
            {blogPosts.map((post) => (
              <article
                key={post.id}
                className="flex max-w-xl flex-col items-start justify-start"
              >
                <div className="relative w-full">
                  <img
                    src={post.cover_image ?? '/images/nextbase-logo.png'}
                    alt={post.title}
                    className="aspect-[16/9] w-full rounded-2xl bg-neutral-100 object-cover sm:aspect-[2/1] lg:aspect-[3/2]"
                  />
                </div>
                <div className="max-w-xl">
                  <div className="mt-5 flex items-center gap-x-4 text-xs">
                    <time
                      dateTime={post.created_at}
                      className="text-neutral-500 uppercase"
                    >
                      {moment(post.created_at).format('MMM D, YYYY')}
                    </time>
                  </div>
                  <div className="group relative">
                    <h3 className="mt-2 text-2xl font-semibold text-neutral-900 group-hover:text-neutral-600">
                      <a href={`/blog/${post.slug}`}>
                        <span className="absolute inset-0" />
                        {post.title}
                      </a>
                    </h3>
                    <p className="mt-2 line-clamp-3 text-base text-neutral-600">
                      {post.summary}
                    </p>
                  </div>
                </div>
              </article>
            ))}
          </div>
        </div>
      ) : (
        <T.Subtle className="text-center">No blog posts yet.</T.Subtle>
      )}
    </>
  );
}
