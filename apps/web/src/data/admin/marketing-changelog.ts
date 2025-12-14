"use server";

import { cacheLife } from "next/cache";
import { redirect } from "@/i18n/navigation";
import { adminActionClient } from "@/lib/safe-action";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { remoteCache } from "@/typed-cache-tags";
import { serverGetRefererLocale } from "@/utils/server/server-get-referer-locale";
import {
  createMarketingChangelogActionSchema,
  deleteMarketingChangelogSchema,
  updateChangelogAuthorsSchema,
  updateMarketingChangelogActionSchema,
} from "@/utils/zod-schemas/marketing-changelog";

export const createChangelogAction = adminActionClient
  .inputSchema(createMarketingChangelogActionSchema)
  .action(async ({ parsedInput }) => {
    const { stringified_json_content, ...createData } = parsedInput;
    const jsonContent = JSON.parse(stringified_json_content);
    const { data, error } = await supabaseAdminClient
      .from("marketing_changelog")
      .insert({
        ...createData,
        json_content: jsonContent,
      })
      .select()
      .single();

    if (error) throw new Error(error.message);

    // Always invalidate admin cache
    remoteCache.admin.changelog.items.list.updateTag();
    // Only invalidate public cache if published
    if (data.status === "published") {
      remoteCache.public.changelog.items.list.updateTag();
    }
    const locale = await serverGetRefererLocale();
    redirect({
      href: `/app-admin/marketing/changelog/${data.id}`,
      locale,
    });
  });

export const updateChangelogAction = adminActionClient
  .inputSchema(updateMarketingChangelogActionSchema)
  .action(async ({ parsedInput }) => {
    const { id, stringified_json_content, ...updateData } = parsedInput;

    // Fetch old status before update
    const { data: oldChangelog } = await supabaseAdminClient
      .from("marketing_changelog")
      .select("status")
      .eq("id", id)
      .single();

    const jsonContent = JSON.parse(stringified_json_content);
    const { data, error } = await supabaseAdminClient
      .from("marketing_changelog")
      .update({
        ...updateData,
        json_content: jsonContent,
      })
      .eq("id", id)
      .select()
      .single();

    if (error) throw new Error(error.message);

    // Always invalidate admin cache and individual item
    remoteCache.admin.changelog.items.list.updateTag();
    remoteCache.admin.changelog.items.byId.updateTag({ id });
    // Invalidate public cache if old OR new status is published
    if (oldChangelog?.status === "published" || data.status === "published") {
      remoteCache.public.changelog.items.list.updateTag();
    }
    return data;
  });

export const deleteChangelogAction = adminActionClient
  .inputSchema(deleteMarketingChangelogSchema)
  .action(async ({ parsedInput: { id } }) => {
    // Fetch status before deleting
    const { data: changelogData } = await supabaseAdminClient
      .from("marketing_changelog")
      .select("status")
      .eq("id", id)
      .single();

    const { error } = await supabaseAdminClient
      .from("marketing_changelog")
      .delete()
      .eq("id", id);

    if (error) throw new Error(error.message);

    // Always invalidate admin cache and individual item
    remoteCache.admin.changelog.items.list.updateTag();
    remoteCache.admin.changelog.items.byId.updateTag({ id });
    // If was published, invalidate public cache
    if (changelogData?.status === "published") {
      remoteCache.public.changelog.items.list.updateTag();
    }
    return { message: "Changelog deleted successfully" };
  });

export const updateChangelogAuthorsAction = adminActionClient
  .inputSchema(updateChangelogAuthorsSchema)
  .action(async ({ parsedInput: { changelogId, authorIds } }) => {
    // Fetch changelog status before updating authors
    const { data: changelogData } = await supabaseAdminClient
      .from("marketing_changelog")
      .select("status")
      .eq("id", changelogId)
      .single();

    const { error: deleteError } = await supabaseAdminClient
      .from("marketing_changelog_author_relationship")
      .delete()
      .eq("changelog_id", changelogId);

    if (deleteError) throw new Error(deleteError.message);

    const authorRelations = authorIds.map((authorId) => ({
      changelog_id: changelogId,
      author_id: authorId,
    }));

    const { error: insertError } = await supabaseAdminClient
      .from("marketing_changelog_author_relationship")
      .insert(authorRelations);

    if (insertError) throw new Error(insertError.message);

    // Always invalidate admin cache and individual item
    remoteCache.admin.changelog.items.list.updateTag();
    remoteCache.admin.changelog.items.byId.updateTag({ id: changelogId });
    // Only invalidate public cache if published
    if (changelogData?.status === "published") {
      remoteCache.public.changelog.items.list.updateTag();
    }
    return { message: "Changelog authors updated successfully" };
  });

export async function getAllChangelogs() {
  const { data, error } = await supabaseAdminClient
    .from("marketing_changelog")
    .select(
      `
      *,
      marketing_changelog_author_relationship(author_id)
    `
    )
    .order("created_at", { ascending: false });

  if (error) throw new Error(error.message);

  return data;
}

export async function getChangelogById(id: string) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_changelog")
    .select(
      `
      *,
      marketing_changelog_author_relationship(author_id)
    `
    )
    .eq("id", id)
    .single();

  if (error) throw new Error(error.message);

  return data;
}

/**
 * Cached function to get ALL changelog items (drafts + published) for admin view
 * Cache duration: 1 hour (balanced freshness)
 */
export async function cachedGetAllChangelogs() {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.admin.changelog.items.list.cacheTag();

  const { data, error } = await supabaseAdminClient
    .from("marketing_changelog")
    .select(
      `
      *,
      marketing_changelog_author_relationship(author_id)
    `
    )
    .order("created_at", { ascending: false });

  if (error) throw new Error(error.message);

  return data;
}
