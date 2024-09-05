import { T } from '@/components/ui/Typography';
import { Metadata } from 'next';
import { z } from 'zod';
import { PublicBlogList } from '../../PublicBlogList';
import { TagsNav } from '../../TagsNav';
import {
  anonGetAllBlogTags,
  anonGetPublishedBlogPosts,
  anonGetPublishedBlogPostsByTagSlug,
  anonGetTagBySlug,
} from '@/data/anon/internalBlog';
import { Suspense } from 'react';

const BlogListByTagPageParamsSchema = z.object({
  tagSlug: z.string(),
});

export async function generateMetadata({
  params,
}: {
  params: unknown;
}): Promise<Metadata> {
  // read route params
  const { tagSlug } = BlogListByTagPageParamsSchema.parse(params);
  const tag = await anonGetTagBySlug(tagSlug);

  return {
    title: `${tag.name} | Blog | Nextbase Ultimate`,
    description: tag.description,
  };
}

async function Tags() {
  const tags = await anonGetAllBlogTags();
  return <TagsNav tags={tags} />;
}

async function BlogList({ tagSlug }: { tagSlug: string }) {
  const blogPosts = await anonGetPublishedBlogPostsByTagSlug(tagSlug);
  return <PublicBlogList blogPosts={blogPosts} />;
}

export default async function BlogListByTagPage({
  params,
}: {
  params: unknown;
}) {
  const { tagSlug } = BlogListByTagPageParamsSchema.parse(params);

  const tag = await anonGetTagBySlug(tagSlug);

  return (
    <div className="space-y-8 w-full">
      <div className="flex items-center flex-col space-y-4">
        <div className="space-y-3 text-center">
          <T.Subtle>Blog</T.Subtle>
          <T.H1>{tag.name}</T.H1>
          <T.Subtle>{tag.description}</T.Subtle>
        </div>
        <Suspense fallback={<T.Subtle>Loading tags...</T.Subtle>}>
          <Tags />
        </Suspense>
      </div>
      <Suspense fallback={<T.Subtle>Loading posts...</T.Subtle>}>
        <BlogList tagSlug={tagSlug} />
      </Suspense>
    </div>
  );
}
