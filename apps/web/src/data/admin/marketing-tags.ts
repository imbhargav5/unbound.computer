"use server";

import { adminActionClient } from "@/lib/safe-action";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { remoteCache } from "@/typed-cache-tags";
import {
  createMarketingTagSchema,
  deleteMarketingTagSchema,
  updateMarketingTagSchema,
} from "@/utils/zod-schemas/marketing-tags";

/**
 * Creates a new marketing tag.
 */
export const createMarketingTagAction = adminActionClient
  .inputSchema(createMarketingTagSchema)
  .action(async ({ parsedInput }) => {
    const { data, error } = await supabaseAdminClient
      .from("marketing_tags")
      .insert(parsedInput)
      .select()
      .single();

    if (error) throw new Error(error.message);

    remoteCache.admin.blog.tags.bySlug.updateTag({ slug: data.slug });
    return data;
  });

/**
 * Updates an existing marketing tag.
 */
export const updateMarketingTagAction = adminActionClient
  .inputSchema(updateMarketingTagSchema)
  .action(async ({ parsedInput }) => {
    const { id, ...updateData } = parsedInput;

    const { data, error } = await supabaseAdminClient
      .from("marketing_tags")
      .update(updateData)
      .eq("id", id)
      .select()
      .single();

    if (error) throw new Error(error.message);

    remoteCache.admin.blog.tags.bySlug.updateTag({ slug: data.slug });
    return data;
  });

/**
 * Deletes a marketing tag.
 */
export const deleteMarketingTagAction = adminActionClient
  .inputSchema(deleteMarketingTagSchema)
  .action(async ({ parsedInput: { id } }) => {
    // Get the slug before deleting for cache invalidation
    const { data: tagData } = await supabaseAdminClient
      .from("marketing_tags")
      .select("slug")
      .eq("id", id)
      .single();

    const { error } = await supabaseAdminClient
      .from("marketing_tags")
      .delete()
      .eq("id", id);

    if (error) throw new Error(error.message);

    if (tagData?.slug) {
      remoteCache.admin.blog.tags.bySlug.updateTag({ slug: tagData.slug });
    }
    return { message: "Tag deleted successfully" };
  });

/**
 * Retrieves all marketing tags.
 */
export async function getAllMarketingTags() {
  const { data, error } = await supabaseAdminClient
    .from("marketing_tags")
    .select("*")
    .order("name", { ascending: true });

  if (error) throw new Error(error.message);

  return data;
}

/**
 * Retrieves a single marketing tag by ID.
 */
export async function getMarketingTagById(id: string) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_tags")
    .select("*")
    .eq("id", id)
    .single();

  if (error) throw new Error(error.message);

  return data;
}
