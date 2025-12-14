"use server";
import type { Tables } from "database/types";
import { cacheLife } from "next/cache";
import { createSupabaseAnonServerClient } from "@/supabase-clients/anon/create-supabase-anon-server-client";
import { supabaseAnonClient } from "@/supabase-clients/anon/supabase-anon-client";
import { remoteCache } from "@/typed-cache-tags";

export async function anonGetAllChangelogItems(): Promise<
  Tables<"marketing_changelog">[]
> {
  const changelogItemsResponse = await supabaseAnonClient
    .from("marketing_changelog")
    .select("*")
    .eq("status", "published")
    .order("created_at", { ascending: false });

  if (changelogItemsResponse.error) {
    throw changelogItemsResponse.error;
  }

  if (!changelogItemsResponse.data) {
    throw new Error("No data found");
  }

  return changelogItemsResponse.data;
}

/**
 * Cached function to get all PUBLISHED changelog items for public view
 * Cache duration: 1 hour (balanced freshness)
 */
export async function cachedGetAllChangelogItems(): Promise<
  Tables<"marketing_changelog">[]
> {
  "use cache: remote";
  cacheLife("hours");
  remoteCache.public.changelog.items.list.cacheTag();

  const supabase = await createSupabaseAnonServerClient();
  const changelogItemsResponse = await supabase
    .from("marketing_changelog")
    .select("*")
    .eq("status", "published")
    .order("created_at", { ascending: false });

  if (changelogItemsResponse.error) {
    throw changelogItemsResponse.error;
  }

  if (!changelogItemsResponse.data) {
    throw new Error("No data found");
  }

  return changelogItemsResponse.data;
}
