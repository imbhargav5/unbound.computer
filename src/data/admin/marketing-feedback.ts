"use server";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabaseAdminClient";
import type { Enum } from "@/types";
import { serverGetLoggedInUser } from "@/utils/server/serverGetLoggedInUser";
import { revalidatePath } from "next/cache";
import { adminToggleFeedbackOpenForCommentsAction } from "../feedback";

export const getPaginatedInternalFeedbackList = async ({
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
  types?: Array<Enum<"marketing_feedback_thread_type">>;
  statuses?: Array<Enum<"marketing_feedback_thread_status">>;
  priorities?: Array<Enum<"marketing_feedback_thread_priority">>;
  sort?: "asc" | "desc";
}) => {
  const zeroIndexedPage = page - 1;
  let supabaseQuery = supabaseAdminClient
    .from("marketing_feedback_threads")
    .select("*")
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

  if (sort === "asc") {
    supabaseQuery = supabaseQuery.order("created_at", { ascending: true });
  } else {
    supabaseQuery = supabaseQuery.order("created_at", { ascending: false });
  }

  const { data, count, error } = await supabaseQuery;

  if (error) {
    throw error;
  }

  return {
    data,
    count,
  };
};

export async function getInternalFeedbackTotalPages({
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
  types?: Array<Enum<"marketing_feedback_thread_type">>;
  statuses?: Array<Enum<"marketing_feedback_thread_status">>;
  priorities?: Array<Enum<"marketing_feedback_thread_priority">>;
  sort?: "asc" | "desc";
}) {
  const zeroIndexedPage = page - 1;
  let supabaseQuery = supabaseAdminClient
    .from("marketing_feedback_threads")
    .select("id", {
      count: "exact",
      head: true,
    })
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

  if (sort === "asc") {
    supabaseQuery = supabaseQuery.order("created_at", { ascending: true });
  } else {
    supabaseQuery = supabaseQuery.order("created_at", { ascending: false });
  }

  const { count, error } = await supabaseQuery;
  if (error) {
    throw error;
  }

  if (!count) {
    return 0;
  }

  return Math.ceil(count / limit) ?? 0;
}

export async function updateInternalFeedbackStatus(
  feedbackId: string,
  status: Enum<"marketing_feedback_thread_status">,
) {
  const { error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ status })
    .eq("id", feedbackId);

  if (error) {
    throw error;
  }
}

export async function updateInternalFeedbackPriority(
  feedbackId: string,
  priority: Enum<"marketing_feedback_thread_priority">,
) {
  const { error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ priority })
    .eq("id", feedbackId);

  if (error) {
    throw error;
  }
}

export const updateInternalFeedbackType = async (
  feedbackId: string,
  type: Enum<"marketing_feedback_thread_type">,
) => {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ type })
    .eq("id", feedbackId);

  if (error) {
    throw error;
  }

  return data;
};

export async function createInternalFeedback(
  userId: string,
  payload: {
    title: string;
    content: string;
    type: Enum<"marketing_feedback_thread_type">;
  },
) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .insert({
      title: payload.title,
      content: payload.content,
      type: payload.type,
      user_id: userId,
    })
    .select("*");

  if (error) {
    throw error;
  }

  return data[0];
}

export async function createInternalFeedbackComment(
  feedbackId: string,
  userId: string,
  content: string,
) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_comments")
    .insert({ thread_id: feedbackId, user_id: userId, content })
    .select("*");

  if (error) {
    throw error;
  }

  return data[0];
}

export async function toggleFeedbackThreadVisibility(
  threadId: string,
  isVisible: boolean,
) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ added_to_roadmap: isVisible })
    .eq("id", threadId)
    .select("*");

  if (error) {
    throw error;
  }

  await adminToggleFeedbackOpenForCommentsAction({
    feedbackId: threadId,
    isOpenForComments: isVisible,
  });
}

export async function toggleFeedbackThreadDiscussion(
  threadId: string,
  isOpen: boolean,
) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ open_for_public_discussion: isOpen })
    .eq("id", threadId)
    .select("*");

  if (error) {
    throw error;
  }

  return data;
}

export const appAdminGetSlimInternalFeedback = async (feedbackId: string) => {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .select("title,content,status")
    .eq("id", feedbackId)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const appAdminAddCommentToInternalFeedbackThread = async (
  feedbackId: string,
  content: string,
) => {
  const user = await serverGetLoggedInUser();
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_comments")
    .insert({ thread_id: feedbackId, user_id: user.id, content })
    .select("*");

  if (error) {
    throw error;
  }

  revalidatePath(`/feedback`, "layout");
  revalidatePath("/app_admin", "layout");

  return data;
};

export const appAdminGetInternalFeedbackComments = async (
  feedbackId: string,
) => {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_comments")
    .select("*")
    .eq("thread_id", feedbackId);

  if (error) {
    throw error;
  }

  return data;
};

export async function adminUpdateInternalFeedbackType({
  feedbackId,
  type,
}: {
  feedbackId: string;
  type: Enum<"marketing_feedback_thread_type">;
}) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ type })
    .eq("id", feedbackId)
    .select("*")
    .single();

  if (error) {
    throw error;
  }
  revalidatePath("/feedback");
  revalidatePath("/feedback");
  return data;
}

export async function adminUpdateInternalFeedbackStatus({
  feedbackId,
  status,
}: {
  feedbackId: string;
  status: Enum<"marketing_feedback_thread_status">;
}) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ status })
    .eq("id", feedbackId)
    .select("*")
    .single();

  if (error) {
    throw error;
  }
  revalidatePath("/feedback");
  revalidatePath("/feedback");
  return data;
}

export async function adminUpdateInternalFeedbackPriority({
  feedbackId,
  priority,
}: {
  feedbackId: string;
  priority: Enum<"marketing_feedback_thread_priority">;
}) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ priority })
    .eq("id", feedbackId)
    .select("*")
    .single();

  if (error) {
    throw error;
  }
  revalidatePath("/feedback", "layout");
  return data;
}

export const adminUpdateInternalFeedbackAddedToRoadmap = async ({
  feedbackId,
  isAddedToRoadmap,
}: {
  feedbackId: string;
  isAddedToRoadmap: boolean;
}) => {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ added_to_roadmap: isAddedToRoadmap })
    .eq("id", feedbackId)
    .select("*");

  if (error) {
    throw error;
  }

  revalidatePath("/feedback", "layout");
  return data;
};

export const adminUpdateInternalFeedbackVisibility = async ({
  feedbackId,
  isOpenToDiscussion,
}: {
  feedbackId: string;
  isOpenToDiscussion: boolean;
}) => {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .update({ open_for_public_discussion: isOpenToDiscussion })
    .eq("id", feedbackId)
    .select("*");

  if (error) {
    throw error;
  }

  revalidatePath("/feedback", "layout");
  return data;
};

export async function adminGetInternalFeedbackById(feedbackId: string) {
  const { data, error } = await supabaseAdminClient
    .from("marketing_feedback_threads")
    .select("*")
    .eq("id", feedbackId);

  if (error) {
    throw error;
  }

  return data[0];
}
