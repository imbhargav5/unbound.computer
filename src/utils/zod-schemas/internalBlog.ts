import { z } from 'zod';

export const marketingAuthorProfileFormSchema = z.object({
  display_name: z.string(),
  bio: z.string(),
  avatar_url: z.string(),
  website_url: z.string().optional(),
  twitter_handle: z.string().optional(),
  facebook_handle: z.string().optional(),
  linkedin_handle: z.string().optional(),
  instagram_handle: z.string().optional(),
  slug: z.string().min(1, { message: 'Slug is required' }),
});

export const marketingBlogPostFormSchema = z.object({
  slug: z.string().min(1, { message: 'Slug is required' }),
  title: z.string().min(1, { message: 'Title is required' }),
  summary: z.string().min(1, { message: 'Summary is required' }),
  content: z
    .string({ required_error: 'Content is required' })
    .min(1, { message: 'Content is required' }),
  is_featured: z.boolean(),
  status: z.enum(['draft', 'published']),
  cover_image: z.string().optional(),
  tags: z
    .object({
      id: z.number(),
      name: z.string(),
    })
    .array(),
  json_content: z.record(z.unknown()),
});

export type MarketingBlogPostFormSchema = z.infer<typeof marketingBlogPostFormSchema>;
