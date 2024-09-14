'use server'

import { adminActionClient } from '@/lib/safe-action';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { toSafeJSONB } from '@/utils/jsonb';
import { createMarketingBlogPostSchema, deleteMarketingBlogPostSchema, updateBlogPostAuthorsSchema, updateBlogPostTagsSchema, updateMarketingBlogPostSchema } from '@/utils/zod-schemas/marketingBlog';
import { revalidatePath } from 'next/cache';
import urlJoin from 'url-join';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { zfd } from "zod-form-data";

/**
 * Creates a new marketing blog post.
 */
export const createBlogPostAction = adminActionClient
  .schema(createMarketingBlogPostSchema)
  .action(async ({ parsedInput }) => {
    const { data, error } = await supabaseAdminClient
      .from('marketing_blog_posts')
      .insert({
        ...parsedInput,
        json_content: toSafeJSONB(parsedInput.json_content),
        seo_data: toSafeJSONB(parsedInput.seo_data),
      })
      .select()
      .single();

    if (error) throw new Error(error.message);

    revalidatePath('/', 'layout');
    return data;
  });

/**
 * Updates an existing marketing blog post.
 */
export const updateBlogPostAction = adminActionClient
  .schema(updateMarketingBlogPostSchema)
  .action(async ({ parsedInput }) => {
    const { id, ...updateData } = parsedInput;

    const { data, error } = await supabaseAdminClient
      .from('marketing_blog_posts')
      .update({
        ...updateData,
        json_content: toSafeJSONB(updateData.json_content),
        seo_data: toSafeJSONB(updateData.seo_data),
      })
      .eq('id', id)
      .select()
      .single();

    if (error) throw new Error(error.message);

    revalidatePath('/', 'layout');
    return data;
  });

/**
 * Deletes a marketing blog post.
 */
export const deleteBlogPostAction = adminActionClient
  .schema(deleteMarketingBlogPostSchema)
  .action(async ({ parsedInput: { id } }) => {
    const { error } = await supabaseAdminClient
      .from('marketing_blog_posts')
      .delete()
      .eq('id', id);

    if (error) throw new Error(error.message);

    revalidatePath('/', 'layout');
    return { message: 'Blog post deleted successfully' };
  });

/**
 * Updates authors for a blog post.
 */
export const updateBlogPostAuthorsAction = adminActionClient
  .schema(updateBlogPostAuthorsSchema)
  .action(async ({ parsedInput: { postId, authorIds } }) => {
    const { error: deleteError } = await supabaseAdminClient
      .from('marketing_blog_author_posts')
      .delete()
      .eq('post_id', postId);

    if (deleteError) throw new Error(deleteError.message);

    const authorRelations = authorIds.map(authorId => ({ post_id: postId, author_id: authorId }));

    const { error: insertError } = await supabaseAdminClient
      .from('marketing_blog_author_posts')
      .insert(authorRelations);

    if (insertError) throw new Error(insertError.message);

    revalidatePath('/', 'layout');
    return { message: 'Blog post authors updated successfully' };
  });

/**
 * Updates tags for a blog post.
 */
export const updateBlogPostTagsAction = adminActionClient
  .schema(updateBlogPostTagsSchema)
  .action(async ({ parsedInput: { postId, tagIds } }) => {
    const { error: deleteError } = await supabaseAdminClient
      .from('marketing_blog_post_tags_relationship')
      .delete()
      .eq('blog_post_id', postId);

    if (deleteError) throw new Error(deleteError.message);

    const tagRelations = tagIds.map(tagId => ({ blog_post_id: postId, tag_id: tagId }));

    const { error: insertError } = await supabaseAdminClient
      .from('marketing_blog_post_tags_relationship')
      .insert(tagRelations);

    if (insertError) throw new Error(insertError.message);

    revalidatePath('/', 'layout');
    return { message: 'Blog post tags updated successfully' };
  });

/**
 * Retrieves all marketing blog posts.
 */
export async function getAllBlogPosts() {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_posts')
    .select(`
      *,
      marketing_blog_author_posts(author_id),
      marketing_blog_post_tags_relationship(tag_id)
    `)
    .order('created_at', { ascending: false });

  if (error) throw new Error(error.message);

  return data;
}

/**
 * Retrieves a single marketing blog post by ID.
 */
export async function getBlogPostById(id: string) {
  const { data, error } = await supabaseAdminClient
    .from('marketing_blog_posts')
    .select(`
      *,
      marketing_blog_author_posts(author_id),
      marketing_blog_post_tags_relationship(tag_id)
    `)
    .eq('id', id)
    .single();

  if (error) throw new Error(error.message);

  return data;
}

const formDataSchema = zfd.formData({
  file: zfd.file(),
});

const uploadBlogCoverImageSchema = z.object({
  formData: formDataSchema,
});

export const uploadBlogCoverImageAction = adminActionClient
  .schema(uploadBlogCoverImageSchema)
  .action(async ({ parsedInput: { formData } }) => {
    const { file } = formData;

    const fileExtension = file.name.split('.').pop();
    const uniqueFilename = `${uuidv4()}.${fileExtension}`;
    const blogImagesPath = `marketing/blog-images/${uniqueFilename}`;

    const { data, error } = await supabaseAdminClient.storage
      .from("marketing-assets")
      .upload(blogImagesPath, file, {
        cacheControl: "3600",
        upsert: true,
      });

    if (error) {
      throw new Error(error.message);
    }

    const { path } = data;

    const filePath = path.split(",")[0];
    const supabaseFileUrl = urlJoin(
      process.env.NEXT_PUBLIC_SUPABASE_URL,
      "/storage/v1/object/public/marketing-assets",
      filePath,
    );

    return supabaseFileUrl;
  });
