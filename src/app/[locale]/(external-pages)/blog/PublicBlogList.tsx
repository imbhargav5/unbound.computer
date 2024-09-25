import { Link } from '@/components/intl-link';
import { T } from '@/components/ui/Typography';
import { anonGetMarketingAuthorById } from "@/data/anon/marketing-authors";
import { DBTable } from '@/types';
import { CalendarDays } from "lucide-react";
import moment from 'moment';
import Image from "next/image";
import { Fragment } from 'react';


async function AuthorProfile({ authorId }: { authorId: string }) {
  if (authorId) {
    const author = await anonGetMarketingAuthorById(authorId);
    return (
      <div className="flex items-center text-sm text-gray-500">
        <Image
          src={author.avatar_url}
          alt={author.display_name}
          width={32}
          height={32}
          className="w-8 h-8 rounded-full mr-2 object-cover"
        />
        <span>{author.display_name}</span>
      </div>
    );
  }
  return null;
}


export function PublicBlogList({
  blogPosts,
}: {
  blogPosts: Array<DBTable<'marketing_blog_posts'> & {
    marketing_blog_author_posts: Array<DBTable<'marketing_blog_author_posts'>>;
  }>;
}) {
  return (
    <Fragment>
      {blogPosts.length ? (
        <div className="grid grid-cols-1 sm:grid-cols-1 md:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5 gap-8">
          {blogPosts.map((post) => {
            const authorId = post.marketing_blog_author_posts[0]?.author_id;
            return (
              <Link href={`/blog/${post.slug}`} key={post.id} className="bg-white rounded-lg shadow-md overflow-hidden">
                <div key={post.id} className="bg-white rounded-lg shadow-md overflow-hidden">
                  <Image
                    src={post.cover_image ?? '/images/nextbase-logo.png'}
                    alt={post.title}
                    width={600}
                    height={400}
                    className="w-full h-48 object-cover"
                  />
                  <div className="p-6">
                    <h2 className="text-xl font-semibold mb-2">{post.title}</h2>
                    <p className="text-gray-600 mb-4">{post.summary}</p>
                    <div className="flex items-center text-sm text-gray-500 mb-2">
                      <CalendarDays className="w-4 h-4 mr-2" />
                      <span>{moment(post.created_at).format('MMM D, YYYY')}</span>
                    </div>
                    <AuthorProfile authorId={authorId} />
                  </div>
                </div>
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
