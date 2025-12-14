// @/data/admin/marketing-blog.ts
"use server";

import { cacheLife, refresh } from "next/cache";
import type { z } from "zod";
import { redirect } from "@/i18n/navigation";
import { adminActionClient } from "@/lib/safe-action";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { remoteCache } from "@/typed-cache-tags";
import type { DBTable } from "@/types";
import { serverGetRefererLocale } from "@/utils/server/server-get-referer-locale";
import {
  createMarketingBlogPostActionSchema,
  deleteMarketingBlogPostSchema,
  updateBlogPostAuthorsSchema,
  updateBlogPostTagsSchema,
  updateMarketingBlogPostActionSchema,
} from "@/utils/zod-schemas/marketing-blog";

/**
 * Creates a new marketing blog post.
 * Utilizes the admin action client to insert a new post into the database.
 * Revalidates the cache path to ensure the new post is reflected in the UI.
 */
export const createBlogPostAction = adminActionClient
  .inputSchema(createMarketingBlogPostActionSchema)
  .action(async ({ parsedInput }) => {
    const { stringified_json_content, stringified_seo_data, ...createData } =
      parsedInput;
    const jsonContent = JSON.parse(stringified_json_content);
    const seoData = JSON.parse(stringified_seo_data);
    const { data, error } = await supabaseAdminClient
      .from("marketing_blog_posts")
      .insert({
        ...createData,
        json_content: jsonContent,
        seo_data: seoData,
      })
      .select()
      .single();

    if (error) throw new Error(error.message);

    // Always invalidate admin's all-posts cache
    remoteCache.admin.blog.posts.list.updateTag();
    // Only invalidate public caches if the post is published
    if (data.status === "published") {
      remoteCache.public.blog.posts.list.revalidateTag();
    }
    const locale = await serverGetRefererLocale();
    redirect({
      href: `/app-admin/marketing/blog/${data.id}`,
      locale,
    });
  });

/**
 * Updates an existing marketing blog post.
 * Uses internal Zod validation and updates a post in the database by its ID.
 * Revalidates the cache path to ensure the updated post is reflected in the UI.
 */
export async function updateBlogPostAction(
  input: z.infer<typeof updateMarketingBlogPostActionSchema>
): Promise<{ data?: DBTable<"marketing_blog_posts">; error?: string }> {
  // Parse with Zod internally
  const parsed = updateMarketingBlogPostActionSchema.safeParse(input);
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message || "Validation failed" };
  }

  const { id, stringified_json_content, stringified_seo_data, ...updateData } =
    parsed.data;

  // Fetch old post data to detect status changes
  const { data: oldPost } = await supabaseAdminClient
    .from("marketing_blog_posts")
    .select("status, slug")
    .eq("id", id)
    .single();

  const jsonContent = JSON.parse(stringified_json_content);
  const seoData = JSON.parse(stringified_seo_data);
  const { data, error } = await supabaseAdminClient
    .from("marketing_blog_posts")
    .update({
      ...updateData,
      json_content: jsonContent,
      seo_data: seoData,
    })
    .eq("id", id)
    .select("*")
    .single();

  if (error) {
    return { error: error.message };
  }

  console.log("updated blog post", data);
  // Always invalidate admin's all-posts cache and individual post cache
  remoteCache.admin.blog.updateTag();
  // Invalidate published posts cache if old OR new status is published
  const statusChanged = oldPost?.status !== data.status;
  const isCurrentlyPublished = data.status === "published";
  if (statusChanged || isCurrentlyPublished) {
    remoteCache.public.blog.posts.list.revalidateTag();
    remoteCache.public.blog.posts.bySlug.revalidateTag({ slug: data.slug });
  }
  refresh();
  return { data };
}

/**
 * Deletes a marketing blog post.
 * Removes a post from the database by its ID using the admin action client.
 * Revalidates the cache path to ensure the deletion is reflected in the UI.
 */
export const deleteBlogPostAction = adminActionClient
  .inputSchema(deleteMarketingBlogPostSchema)
  .action(async ({ parsedInput: { id } }) => {
    // Get post data, tags, and authors before deleting for cache invalidation
    const { data: postData } = await supabaseAdminClient
      .from("marketing_blog_posts")
      .select(
        "slug, status, marketing_blog_post_tags_relationship(marketing_tags(slug)), marketing_blog_author_posts(author_id)"
      )
      .eq("id", id)
      .single();

    const { error } = await supabaseAdminClient
      .from("marketing_blog_posts")
      .delete()
      .eq("id", id);

    if (error) throw new Error(error.message);

    // Always invalidate admin and individual post caches
    if (postData?.slug) {
      remoteCache.admin.blog.posts.bySlug.updateTag({
        slug: postData.slug,
      });
    }
    remoteCache.admin.blog.posts.list.updateTag();

    // If post was published, invalidate all public caches
    if (postData?.status === "published") {
      remoteCache.public.blog.posts.list.revalidateTag();

      // Invalidate tag-specific caches
      if (postData.marketing_blog_post_tags_relationship) {
        for (const tagRel of postData.marketing_blog_post_tags_relationship) {
          if (tagRel.marketing_tags?.slug) {
            remoteCache.public.blog.posts.byTagSlug.revalidateTag({
              slug: tagRel.marketing_tags.slug,
            });
          }
        }
      }

      // Invalidate author-specific caches
      if (postData.marketing_blog_author_posts) {
        for (const authorPost of postData.marketing_blog_author_posts) {
          if (authorPost.author_id) {
            remoteCache.public.blog.posts.byAuthorId.revalidateTag({
              authorId: authorPost.author_id,
            });
          }
        }
      }
    }

    return { message: "Blog post deleted successfully" };
  });

/**
 * Updates authors for a blog post.
 * Deletes existing author relationships and inserts new ones for a given post.
 * Revalidates the cache path to ensure the author updates are reflected in the UI.
 */
export const updateBlogPostAuthorsAction = adminActionClient
  .inputSchema(updateBlogPostAuthorsSchema)
  .action(async ({ parsedInput: { postId, authorIds } }) => {
    // Fetch post status, slug, and old authors before updating
    const { data: postData } = await supabaseAdminClient
      .from("marketing_blog_posts")
      .select("status, slug, marketing_blog_author_posts(author_id)")
      .eq("id", postId)
      .single();

    const oldAuthorIds = new Set(
      postData?.marketing_blog_author_posts?.map((rel) => rel.author_id) || []
    );

    const { error: deleteError } = await supabaseAdminClient
      .from("marketing_blog_author_posts")
      .delete()
      .eq("post_id", postId);

    if (deleteError) throw new Error(deleteError.message);

    const authorRelations = authorIds.map((authorId) => ({
      post_id: postId,
      author_id: authorId,
    }));

    const { error: insertError } = await supabaseAdminClient
      .from("marketing_blog_author_posts")
      .insert(authorRelations);

    if (insertError) throw new Error(insertError.message);

    // Always invalidate admin caches
    remoteCache.admin.blog.posts.list.updateTag();
    remoteCache.admin.blog.authors.list.updateTag();
    if (postData?.slug) {
      remoteCache.admin.blog.posts.bySlug.updateTag({
        slug: postData.slug,
      });
    }

    // Only invalidate published caches if post is published
    if (postData?.status === "published") {
      remoteCache.public.blog.posts.list.revalidateTag();

      // Invalidate old author caches (authors that were removed)
      for (const authorId of oldAuthorIds) {
        if (authorId) {
          remoteCache.public.blog.posts.byAuthorId.revalidateTag({ authorId });
        }
      }

      // Invalidate new author caches (authors that were added)
      for (const authorId of authorIds) {
        remoteCache.public.blog.posts.byAuthorId.revalidateTag({ authorId });
      }
    }

    return { message: "Blog post authors updated successfully" };
  });

/**
 * Updates tags for a blog post.
 * Deletes existing tag relationships and inserts new ones for a given post.
 * Revalidates the cache path to ensure the tag updates are reflected in the UI.
 */
export const updateBlogPostTagsAction = adminActionClient
  .inputSchema(updateBlogPostTagsSchema)
  .action(async ({ parsedInput: { postId, tagIds } }) => {
    // Fetch post status, slug, and old tags before updating
    const { data: postData } = await supabaseAdminClient
      .from("marketing_blog_posts")
      .select(
        "status, slug, marketing_blog_post_tags_relationship(marketing_tags(id, slug))"
      )
      .eq("id", postId)
      .single();

    const oldTagSlugs = new Set(
      postData?.marketing_blog_post_tags_relationship
        ?.map((rel) => rel.marketing_tags?.slug)
        .filter(Boolean) || []
    );

    const { error: deleteError } = await supabaseAdminClient
      .from("marketing_blog_post_tags_relationship")
      .delete()
      .eq("blog_post_id", postId);

    if (deleteError) throw new Error(deleteError.message);

    const tagRelations = tagIds.map((tagId) => ({
      blog_post_id: postId,
      tag_id: tagId,
    }));

    const { error: insertError } = await supabaseAdminClient
      .from("marketing_blog_post_tags_relationship")
      .insert(tagRelations);

    if (insertError) throw new Error(insertError.message);

    // Get new tag slugs
    const { data: newTags } = await supabaseAdminClient
      .from("marketing_tags")
      .select("slug")
      .in("id", tagIds);

    const newTagSlugs = new Set(newTags?.map((tag) => tag.slug) || []);

    // Always invalidate admin caches
    remoteCache.admin.blog.posts.list.updateTag();
    remoteCache.admin.blog.tags.list.updateTag();
    if (postData?.slug) {
      remoteCache.admin.blog.posts.bySlug.updateTag({
        slug: postData.slug,
      });
    }

    // Only invalidate published caches if post is published
    if (postData?.status === "published") {
      remoteCache.public.blog.posts.list.revalidateTag();

      // Invalidate old tag caches (tags that were removed)
      for (const tagSlug of oldTagSlugs) {
        if (tagSlug) {
          remoteCache.public.blog.posts.byTagSlug.revalidateTag({
            slug: tagSlug,
          });
        }
      }

      // Invalidate new tag caches (tags that were added)
      for (const tagSlug of newTagSlugs) {
        if (tagSlug) {
          remoteCache.public.blog.posts.byTagSlug.revalidateTag({
            slug: tagSlug,
          });
        }
      }
    }

    return { message: "Blog post tags updated successfully" };
  });

/**
 * Retrieves all marketing blog posts.
 * Fetches all posts from the database, including their authors and tags.
 * Orders the posts by creation date in descending order.
 */
export async function getAllBlogPosts() {
  const { data, error } = await supabaseAdminClient
    .from("marketing_blog_posts")
    .select(
      `
      *,
      marketing_blog_author_posts(author_id),
      marketing_blog_post_tags_relationship(tag_id)
    `
    )
    .order("created_at", { ascending: false });

  if (error) throw new Error(error.message);

  return data;
}

/**
 * Retrieves a single marketing blog post by ID.
 * Fetches a post from the database by its ID, including its authors and tags.
 */
export async function getBlogPostById(id: string) {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.admin.blog.posts.byId.cacheTag({ id });

  const { data, error } = await supabaseAdminClient
    .from("marketing_blog_posts")
    .select(
      `
      *,
      marketing_blog_author_posts(author_id),
      marketing_blog_post_tags_relationship(tag_id)
    `
    )
    .eq("id", id)
    .single();

  if (error) throw new Error(error.message);

  return data;
}

/**
 * Cached function to get ALL blog posts (drafts + published) for admin view
 * Cache duration: 1 hour (balanced freshness)
 */
export async function cachedGetAllBlogPosts() {
  "use cache: remote";
  remoteCache.admin.blog.posts.list.cacheTag();

  const { data, error } = await supabaseAdminClient
    .from("marketing_blog_posts")
    .select(
      `
      *,
      marketing_blog_author_posts(author_id),
      marketing_blog_post_tags_relationship(tag_id)
    `
    )
    .order("created_at", { ascending: false });

  if (error) throw new Error(error.message);

  return data;
}
