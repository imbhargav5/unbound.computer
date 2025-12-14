"use server";

import type { Database } from "database/types";
import { cacheLife } from "next/cache";
import { createSupabaseAnonServerClient } from "@/supabase-clients/anon/create-supabase-anon-server-client";
import { supabaseAnonClient } from "@/supabase-clients/anon/supabase-anon-client";
import { remoteCache } from "@/typed-cache-tags";

type MarketingFeedbackThread =
  Database["public"]["Tables"]["marketing_feedback_threads"]["Row"];
type MarketingFeedbackThreadType =
  Database["public"]["Enums"]["marketing_feedback_thread_type"];
type MarketingFeedbackThreadStatus =
  Database["public"]["Enums"]["marketing_feedback_thread_status"];
type MarketingFeedbackThreadPriority =
  Database["public"]["Enums"]["marketing_feedback_thread_priority"];
type MarketingFeedbackBoard =
  Database["public"]["Tables"]["marketing_feedback_boards"]["Row"];

export async function getAnonUserFeedbackList({
  query = "",
  types = [],
  statuses = [],
  priorities = [],
  page = 1,
  limit = 10,
}: {
  page?: number;
  limit?: number;
  query?: string;
  types?: MarketingFeedbackThreadType[];
  statuses?: MarketingFeedbackThreadStatus[];
  priorities?: MarketingFeedbackThreadPriority[];
}) {
  "use cache: remote";
  remoteCache.public.feedback.list.cacheTag();
  const zeroIndexedPage = page - 1;

  let supabaseQuery = supabaseAnonClient
    .from("marketing_feedback_threads")
    .select(
      `
      *,
      marketing_feedback_comments!thread_id(count),
      marketing_feedback_thread_reactions!thread_id(count)
    `
    )
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null)
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("title", `%${query}%`);
  }

  if (types.length > 0) {
    supabaseQuery = supabaseQuery.in("type", types);
  }

  if (statuses.length > 0) {
    supabaseQuery = supabaseQuery.in("status", statuses);
  }

  if (priorities.length > 0) {
    supabaseQuery = supabaseQuery.in("priority", priorities);
  }

  supabaseQuery = supabaseQuery.order("created_at", {
    ascending: false,
  });

  const { data, count, error } = await supabaseQuery;
  if (error) {
    throw error;
  }

  return {
    data: data?.map((thread) => ({
      ...thread,
      comment_count: thread.marketing_feedback_comments[0]?.count ?? 0,
      reaction_count: thread.marketing_feedback_thread_reactions[0]?.count ?? 0,
    })),
    count: count ?? 0,
  };
}

export async function getAnonUserFeedbackCommentsByThreadId(threadId: string) {
  "use cache: remote";
  remoteCache.public.feedback.comments.byThreadId.list.cacheTag({ threadId });
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_comments")
    .select("*")
    .eq("thread_id", threadId);
  if (error) {
    throw error;
  }

  return data;
}

export async function getAnonUserFeedbackReactionsByThreadId(threadId: string) {
  "use cache: remote";
  remoteCache.public.feedback.reactions.byThreadId.list.cacheTag({ threadId });
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_thread_reactions")
    .select("*")
    .eq("thread_id", threadId);
  if (error) {
    throw error;
  }

  return data;
}

export async function getAnonUserFeedbackCommentsCountByThreadId(
  threadId: string
) {
  "use cache: remote";
  remoteCache.public.feedback.comments.byThreadId.count.cacheTag({ threadId });
  const { count, error } = await supabaseAnonClient
    .from("marketing_feedback_comments")
    .select("count", { count: "exact", head: true })
    .eq("thread_id", threadId);
  if (error) {
    throw error;
  }

  return count ?? 0;
}

export async function getAnonUserFeedbackReactionsCountByThreadId(
  threadId: string
) {
  "use cache: remote";
  remoteCache.public.feedback.reactions.byThreadId.count.cacheTag({ threadId });
  const { count, error } = await supabaseAnonClient
    .from("marketing_feedback_thread_reactions")
    .select("count", { count: "exact", head: true })
    .eq("thread_id", threadId);
  if (error) {
    throw error;
  }

  return count ?? 0;
}

export async function getAnonUserFeedbackTotalPages({
  query = "",
  types = [],
  statuses = [],
  priorities = [],
  limit = 10,
}: {
  query?: string;
  types?: MarketingFeedbackThreadType[];
  statuses?: MarketingFeedbackThreadStatus[];
  priorities?: MarketingFeedbackThreadPriority[];
  limit?: number;
}): Promise<number> {
  "use cache: remote";
  remoteCache.public.feedback.list.cacheTag();
  let supabaseQuery = supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*", { count: "exact", head: true })
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("title", `%${query}%`);
  }

  if (types.length > 0) {
    supabaseQuery = supabaseQuery.in("type", types);
  }

  if (statuses.length > 0) {
    supabaseQuery = supabaseQuery.in("status", statuses);
  }

  if (priorities.length > 0) {
    supabaseQuery = supabaseQuery.in("priority", priorities);
  }

  const { count, error } = await supabaseQuery;
  if (error) {
    throw error;
  }

  if (!count) {
    return 0;
  }

  return Math.ceil(count / limit);
}

export async function anonGetRoadmapFeedbackList(): Promise<
  MarketingFeedbackThread[]
> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select(
      `
      *,
      marketing_feedback_comments!thread_id(count),
      marketing_feedback_thread_reactions!thread_id(count)
    `
    )
    .eq("added_to_roadmap", true)
    .is("moderator_hold_category", null);

  if (error) {
    throw error;
  }

  return data?.map((thread) => ({
    ...thread,
    comment_count: thread.marketing_feedback_comments[0]?.count ?? 0,
    reaction_count: thread.marketing_feedback_thread_reactions[0]?.count ?? 0,
  }));
}

async function getRoadmapFeedbackByStatus(
  status: MarketingFeedbackThreadStatus
): Promise<MarketingFeedbackThread[]> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select(
      `
      *,
      marketing_feedback_comments!thread_id(count),
      marketing_feedback_thread_reactions!thread_id(count)
    `
    )
    .eq("added_to_roadmap", true)
    .eq("status", status)
    .is("moderator_hold_category", null);

  if (error) {
    throw error;
  }

  return data?.map((thread) => ({
    ...thread,
    comment_count: thread.marketing_feedback_comments[0]?.count ?? 0,
    reaction_count: thread.marketing_feedback_thread_reactions[0]?.count ?? 0,
  }));
}

export async function anonGetPlannedRoadmapFeedbackList() {
  return getRoadmapFeedbackByStatus("planned");
}
export async function anonGetInProgressRoadmapFeedbackList() {
  return getRoadmapFeedbackByStatus("in_progress");
}
export async function anonGetCompletedRoadmapFeedbackList() {
  return getRoadmapFeedbackByStatus("completed");
}

// Add this new function
export async function getAnonUserFeedbackById(
  feedbackId: string
): Promise<MarketingFeedbackThread | null> {
  "use cache: remote";
  remoteCache.public.feedback.threads.byId.cacheTag({ id: feedbackId });
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*")
    .eq("id", feedbackId)
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null)
    .single();

  if (error) {
    console.error("Error fetching feedback:", error);
    return null;
  }

  return data;
}

export async function getRecentPublicFeedback() {
  "use cache: remote";
  remoteCache.public.feedback.recent.cacheTag();
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("id, title, created_at")
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null)
    .order("created_at", { ascending: false })
    .limit(3);

  if (error) {
    console.error("Error fetching recent feedback:", error);
    return [];
  }

  return data;
}

/**
 * Retrieves all active feedback boards visible to anonymous users.
 * @returns Array of active feedback boards
 */
export async function getAnonFeedbackBoards(): Promise<
  MarketingFeedbackBoard[]
> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_boards")
    .select("*")
    .eq("is_active", true)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Gets a specific active feedback board by its ID.
 * @param boardId - The ID of the board to retrieve
 * @returns The feedback board data or null if not found/inactive
 */
export async function getAnonFeedbackBoardById(
  boardId: string
): Promise<MarketingFeedbackBoard | null> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_boards")
    .select("*")
    .eq("id", boardId)
    .eq("is_active", true)
    .single();

  if (error) {
    return null;
  }

  return data;
}

/**
 * Gets all visible feedback threads for a specific board.
 * @param boardId - The ID of the board to get threads for
 * @returns Array of visible feedback threads in the board
 */
export async function getAnonFeedbackThreadsByBoardId(
  boardId: string
): Promise<MarketingFeedbackThread[]> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select(
      `*,
      marketing_feedback_comments!thread_id(count),
      marketing_feedback_thread_reactions!thread_id(count)
    `
    )
    .eq("board_id", boardId)
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data?.map((thread) => ({
    ...thread,
    comment_count: thread.marketing_feedback_comments[0]?.count ?? 0,
    reaction_count: thread.marketing_feedback_thread_reactions[0]?.count ?? 0,
  }));
}

/**
 * Gets paginated visible feedback threads for a specific board with filtering.
 */
export async function getPaginatedAnonFeedbackThreadsByBoardId({
  boardId,
  query = "",
  types = [],
  statuses = [],
  priorities = [],
  page = 1,
  limit = 10,
}: {
  boardId: string;
  page?: number;
  limit?: number;
  query?: string;
  types?: MarketingFeedbackThreadType[];
  statuses?: MarketingFeedbackThreadStatus[];
  priorities?: MarketingFeedbackThreadPriority[];
}) {
  const zeroIndexedPage = page - 1;
  let supabaseQuery = supabaseAnonClient
    .from("marketing_feedback_threads")
    .select(
      `*,
      marketing_feedback_comments!thread_id(count),
      marketing_feedback_thread_reactions!thread_id(count)
    `
    )
    .eq("board_id", boardId)
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null)
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("title", `%${query}%`);
  }

  if (types.length > 0) {
    supabaseQuery = supabaseQuery.in("type", types);
  }

  if (statuses.length > 0) {
    supabaseQuery = supabaseQuery.in("status", statuses);
  }

  if (priorities.length > 0) {
    supabaseQuery = supabaseQuery.in("priority", priorities);
  }
  supabaseQuery = supabaseQuery.order("created_at", { ascending: false });

  const { data, count, error } = await supabaseQuery;

  if (error) {
    throw error;
  }

  return {
    data: data?.map((thread) => ({
      ...thread,
      comment_count: thread.marketing_feedback_comments[0]?.count ?? 0,
      reaction_count: thread.marketing_feedback_thread_reactions[0]?.count ?? 0,
    })),
    count: count ?? 0,
  };
}

/**
 * Gets an active feedback board by its slug for anonymous users.
 */
export async function getAnonFeedbackBoardBySlug(slug: string) {
  "use cache: remote";
  remoteCache.public.feedback.boards.bySlug.cacheTag({ slug });
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_boards")
    .select("*")
    .eq("slug", slug)
    .eq("is_active", true)
    .single();

  if (error) {
    return null;
  }

  return data;
}

/**
 * Gets all visible feedback threads for a specific board by slug with filtering.
 */
export async function getAnonFeedbackThreadsByBoardSlug(
  slug: string,
  {
    query = "",
    types = [],
    statuses = [],
    priorities = [],
  }: {
    query?: string;
    types?: MarketingFeedbackThreadType[];
    statuses?: MarketingFeedbackThreadStatus[];
    priorities?: MarketingFeedbackThreadPriority[];
  } = {}
) {
  const board = await getAnonFeedbackBoardBySlug(slug);
  if (!board) return { data: [], count: 0 };

  let supabaseQuery = supabaseAnonClient
    .from("marketing_feedback_threads")
    .select(
      `*,
      marketing_feedback_comments!thread_id(count),
      marketing_feedback_thread_reactions!thread_id(count)
    `
    )
    .eq("board_id", board.id)
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("title", `%${query}%`);
  }

  if (types.length > 0) {
    supabaseQuery = supabaseQuery.in("type", types);
  }

  if (statuses.length > 0) {
    supabaseQuery = supabaseQuery.in("status", statuses);
  }

  if (priorities.length > 0) {
    supabaseQuery = supabaseQuery.in("priority", priorities);
  }

  supabaseQuery = supabaseQuery.order("created_at", { ascending: false });

  const { data, count, error } = await supabaseQuery;

  if (error) {
    throw error;
  }

  return {
    data: data?.map((thread) => ({
      ...thread,
      comment_count: thread.marketing_feedback_comments[0]?.count ?? 0,
      reaction_count: thread.marketing_feedback_thread_reactions[0]?.count ?? 0,
    })),
    count: count ?? 0,
  };
}
/**
 * Retrieves all comments for a specific feedback thread for anonymous users.
 * Only returns comments for threads that are publicly visible.
 * @param feedbackId - The ID of the feedback thread
 * @returns Array of comments for the thread
 */
export async function getAnonFeedbackComments(feedbackId: string) {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_comments")
    .select("*")
    .eq("thread_id", feedbackId)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data;
}

// ============================================
// Cached functions (from cached-data/anon/marketing-feedback.ts)
// ============================================

/**
 * Cached function to get all active feedback boards
 * Cache duration: 5 minutes (balanced for semi-dynamic content)
 */
export async function cachedGetAnonFeedbackBoards(): Promise<
  MarketingFeedbackBoard[]
> {
  "use cache: remote";
  cacheLife("minutes");
  remoteCache.public.feedback.boards.list.cacheTag();

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_feedback_boards")
    .select("*")
    .eq("is_active", true)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}

export async function cachedGetAnonFeedbackBoardBySlug(slug: string) {
  "use cache: remote";
  cacheLife("minutes");
  remoteCache.public.feedback.boards.bySlug.cacheTag({ slug });

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_feedback_boards")
    .select("*")
    .eq("slug", slug)
    .eq("is_active", true)
    .single();

  if (error) {
    return null;
  }

  return data;
}

/**
 * Cached function to get recent public feedback
 * Cache duration: 5 minutes
 */
export async function cachedGetRecentPublicFeedback() {
  "use cache: remote";
  remoteCache.public.feedback.recent.cacheTag();

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_feedback_threads")
    .select("id, title, created_at")
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null)
    .order("created_at", { ascending: false })
    .limit(3);

  if (error) {
    console.error("Error fetching recent feedback:", error);
    return [];
  }

  return data;
}

export async function cachedGetAnonUserFeedbackById(
  feedbackId: string
): Promise<MarketingFeedbackThread | null> {
  "use cache: remote";
  cacheLife("minutes");
  remoteCache.public.feedback.threads.byId.cacheTag({ id: feedbackId });

  const supabase = await createSupabaseAnonServerClient();
  const { data, error } = await supabase
    .from("marketing_feedback_threads")
    .select("*")
    .eq("id", feedbackId)
    .is("is_publicly_visible", true)
    .is("moderator_hold_category", null)
    .single();

  if (error) {
    console.error("Error fetching feedback:", error);
    return null;
  }

  return data;
}
