"use server";

import { Database } from "@/lib/database.types";
import { supabaseAnonClient } from "@/supabase-clients/anon/supabaseAnonClient";

type MarketingFeedbackThread =
  Database["public"]["Tables"]["marketing_feedback_threads"]["Row"];
type MarketingFeedbackThreadType =
  Database["public"]["Enums"]["marketing_feedback_thread_type"];
type MarketingFeedbackThreadStatus =
  Database["public"]["Enums"]["marketing_feedback_thread_status"];
type MarketingFeedbackThreadPriority =
  Database["public"]["Enums"]["marketing_feedback_thread_priority"];
type MarketingFeedbackBoard = Database["public"]["Tables"]["marketing_feedback_boards"]["Row"];

export async function getAnonUserFeedbackList({
  query = "",
  types = [],
  statuses = [],
  priorities = [],
  page = 1,
  limit = 10,
  sort = "desc",
}: {
  page?: number;
  limit?: number;
  query?: string;
  types?: MarketingFeedbackThreadType[];
  statuses?: MarketingFeedbackThreadStatus[];
  priorities?: MarketingFeedbackThreadPriority[];
  sort?: "asc" | "desc";
}) {
  const zeroIndexedPage = page - 1;

  let supabaseQuery = supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*")
    .or(
      "added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true",
    )
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
    ascending: sort === "asc",
  });

  const { data, count, error } = await supabaseQuery;
  if (error) {
    throw error;
  }

  return {
    data,
    count: count ?? 0,
  };
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
  let supabaseQuery = supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*", { count: "exact", head: true })
    .or(
      "added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true",
    )
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
    .select("*")
    .eq("added_to_roadmap", true)
    .is("moderator_hold_category", null);

  if (error) {
    throw error;
  }

  return data;
}

async function getRoadmapFeedbackByStatus(
  status: MarketingFeedbackThreadStatus,
): Promise<MarketingFeedbackThread[]> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*")
    .eq("added_to_roadmap", true)
    .eq("status", status)
    .is("moderator_hold_category", null);

  if (error) {
    throw error;
  }

  return data;
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
  feedbackId: string,
): Promise<MarketingFeedbackThread | null> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*")
    .eq("id", feedbackId)
    .or(
      "added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true",
    )
    .is("moderator_hold_category", null)
    .single();

  if (error) {
    console.error("Error fetching feedback:", error);
    return null;
  }

  return data;
}

export async function getRecentPublicFeedback() {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("id, title, created_at")
    .or(
      "added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true",
    )
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
export async function getAnonFeedbackBoards(): Promise<MarketingFeedbackBoard[]> {
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
  boardId: string,
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
  boardId: string,
): Promise<MarketingFeedbackThread[]> {
  const { data, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*")
    .eq("board_id", boardId)
    .or(
      "added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true",
    )
    .is("moderator_hold_category", null)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data;
}

/**
 * Gets paginated visible feedback threads for a specific board.
 */
export async function getPaginatedAnonFeedbackThreadsByBoardId({
  boardId,
  page = 1,
  limit = 10,
  sort = "desc",
}: {
  boardId: string;
  page?: number;
  limit?: number;
  sort?: "asc" | "desc";
}) {
  const zeroIndexedPage = page - 1;

  const { data, count, error } = await supabaseAnonClient
    .from("marketing_feedback_threads")
    .select("*", { count: "exact" })
    .eq("board_id", boardId)
    .or(
      "added_to_roadmap.eq.true,open_for_public_discussion.eq.true,is_publicly_visible.eq.true",
    )
    .is("moderator_hold_category", null)
    .order("created_at", { ascending: sort === "asc" })
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (error) {
    throw error;
  }

  return {
    data,
    count: count ?? 0,
  };
}
