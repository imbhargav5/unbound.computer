"use server";

import { z } from "zod";
import { adminActionClient, authActionClient } from "@/lib/safe-action";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { supabaseClientBasedOnUserRole } from "@/supabase-clients/user-role-client";
import { remoteCache } from "@/typed-cache-tags";
import { serverGetClaimType } from "@/utils/server/server-get-user-type";
import { userRoles } from "@/utils/user-types";
import {
  marketingFeedbackStatusEnum,
  marketingFeedbackThreadPriorityEnum,
  marketingFeedbackTypeEnum,
} from "@/utils/zod-schemas/feedback";
import {
  createFeedbackAddedToRoadmapUpdatedNotification,
  createFeedbackPriorityChangedNotification,
  createFeedbackReceivedCommentNotification,
  createFeedbackStatusChangedNotification,
  createFeedbackTypeUpdatedNotification,
  createFeedbackVisibilityUpdatedNotification,
  createUpdateFeedbackOpenForCommentsNotification,
} from "./user/notifications";
import { getUserFullName } from "./user/user";

const addCommentToInternalFeedbackThreadSchema = z.object({
  feedbackId: z.string(),
  content: z.string(),
});

export const addCommentToInternalFeedbackThreadAction = authActionClient
  .inputSchema(addCommentToInternalFeedbackThreadSchema)
  .action(async ({ parsedInput: { feedbackId, content }, ctx: { userId } }) => {
    const userRoleType = await serverGetClaimType();
    const supabaseClient = await supabaseClientBasedOnUserRole();

    const { data: feedbackThread, error: feedbackThreadError } =
      await supabaseAdminClient
        .from("marketing_feedback_threads")
        .select("*")
        .eq("id", feedbackId)
        .maybeSingle();

    if (feedbackThreadError) {
      throw feedbackThreadError;
    }

    /**
     * App admins can comment on all feedbacks
     * Normal users can comment on their own feedback or publicly visible feedback
     */
    if (
      !(
        feedbackThread?.is_publicly_visible ||
        feedbackThread?.user_id == userId ||
        userRoleType == userRoles.ADMIN
      )
    ) {
      throw new Error("This feedback is not publicly visible");
    }

    const { data, error } = await supabaseClient
      .from("marketing_feedback_comments")
      .insert({ thread_id: feedbackId, user_id: userId, content })
      .select("*");

    if (error) {
      return {
        status: "error",
        message: error.message,
      };
    }

    const userFullName = await getUserFullName(userId);

    await createFeedbackReceivedCommentNotification({
      feedbackId,
      feedbackTitle: feedbackThread?.title || "",
      comment: content,
      commenterId: userId,
      commenterName: userFullName ?? "User",
    });

    // Invalidate both admin and public caches
    remoteCache.admin.feedback.list.updateTag();
    remoteCache.public.feedback.list.updateTag();
    remoteCache.admin.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.recent.updateTag();
    return data;
  });

const updateMarketingFeedbackCommentSchema = z.object({
  feedbackId: z.string(),
  commentId: z.string(),
  feedbackCommentOwnerId: z.string(),
  content: z.string(),
});

export const ownerUpdateMarketingFeedbackCommentAction = authActionClient
  .inputSchema(updateMarketingFeedbackCommentSchema)
  .action(
    async ({
      parsedInput: { feedbackId, commentId, feedbackCommentOwnerId, content },
      ctx: { userId },
    }) => {
      if (feedbackCommentOwnerId !== userId) {
        return {
          status: "error",
          message: "You are unathorized to perform this action",
        };
      }

      const supabaseClient = await supabaseClientBasedOnUserRole();

      const { data, error } = await supabaseClient
        .from("marketing_feedback_comments")
        .update({ content })
        .eq("id", commentId)
        .eq("thread_id", feedbackId)
        .eq("user_id", feedbackCommentOwnerId);

      if (error) {
        return {
          status: "error",
          message: error.message,
        };
      }
      // Invalidate both admin and public caches
      remoteCache.admin.feedback.list.updateTag();
      remoteCache.public.feedback.list.updateTag();
      remoteCache.admin.feedback.threads.byId.updateTag({
        id: feedbackId,
      });
      remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
      remoteCache.public.feedback.recent.updateTag();
      return data;
    }
  );

export async function muteFeedbackThread({
  feedbackId,
  isMuted,
}: {
  feedbackId: string;
  isMuted: boolean;
}) {
  return null;
  // TODO:
  // for logged in users and admins

  // if (error) {
  //     throw error;
  // }

  // revalidatePath(`/feedbacks`, 'page');
  // revalidatePath(`/feedbacks/[[...feedbackId]]`, 'page');
  // return data;
}

const updateFeedbackStatusSchema = z.object({
  feedbackId: z.string(),
  status: marketingFeedbackStatusEnum,
});

export const adminUpdateFeedbackStatusAction = adminActionClient
  .inputSchema(updateFeedbackStatusSchema)
  .action(async ({ parsedInput: { feedbackId, status }, ctx: { userId } }) => {
    const { data: feedbackThread, error: feedbackThreadError } =
      await supabaseAdminClient
        .from("marketing_feedback_threads")
        .select("user_id, status")
        .eq("id", feedbackId)
        .single();

    if (feedbackThreadError) {
      throw new Error(feedbackThreadError.message);
    }

    const { error } = await supabaseAdminClient
      .from("marketing_feedback_threads")
      .update({ status })
      .eq("id", feedbackId);

    if (error) {
      throw new Error(error.message);
    }

    await createFeedbackStatusChangedNotification({
      feedbackId,
      newStatus: status,
      oldStatus: feedbackThread.status,
      feedbackOwnerId: feedbackThread.user_id,
      statusUpdaterId: userId,
    });

    // Invalidate both admin and public caches
    remoteCache.admin.feedback.list.updateTag();
    remoteCache.public.feedback.list.updateTag();
    remoteCache.admin.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.recent.updateTag();
    // Invalidate roadmap caches
    remoteCache.admin.roadmap.items.list.updateTag();
    remoteCache.public.roadmap.items.list.updateTag();

    return { status };
  });

const updateFeedbackTypeSchema = z.object({
  feedbackId: z.string(),
  type: marketingFeedbackTypeEnum,
});

export const adminUpdateFeedbackTypeAction = adminActionClient
  .inputSchema(updateFeedbackTypeSchema)
  .action(async ({ parsedInput: { feedbackId, type }, ctx: { userId } }) => {
    const { data: feedbackThread, error: feedbackThreadError } =
      await supabaseAdminClient
        .from("marketing_feedback_threads")
        .select("user_id, type")
        .eq("id", feedbackId)
        .single();

    if (feedbackThreadError) {
      throw new Error(feedbackThreadError.message);
    }

    const { error } = await supabaseAdminClient
      .from("marketing_feedback_threads")
      .update({ type })
      .eq("id", feedbackId);

    if (error) {
      throw new Error(error.message);
    }

    await createFeedbackTypeUpdatedNotification({
      feedbackId,
      newType: type,
      oldType: feedbackThread.type,
      feedbackOwnerId: feedbackThread.user_id,
      typeUpdaterId: userId,
    });

    // Invalidate both admin and public caches
    remoteCache.admin.feedback.list.updateTag();
    remoteCache.public.feedback.list.updateTag();
    remoteCache.admin.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.recent.updateTag();

    return { type };
  });

const updateFeedbackPrioritySchema = z.object({
  feedbackId: z.string(),
  priority: marketingFeedbackThreadPriorityEnum,
});

export const adminUpdateFeedbackPriorityAction = adminActionClient
  .inputSchema(updateFeedbackPrioritySchema)
  .action(
    async ({ parsedInput: { feedbackId, priority }, ctx: { userId } }) => {
      const { data: feedbackThread, error: feedbackThreadError } =
        await supabaseAdminClient
          .from("marketing_feedback_threads")
          .select("user_id, priority")
          .eq("id", feedbackId)
          .single();

      if (feedbackThreadError) {
        throw new Error(feedbackThreadError.message);
      }

      const { error } = await supabaseAdminClient
        .from("marketing_feedback_threads")
        .update({ priority })
        .eq("id", feedbackId);

      if (error) {
        throw new Error(error.message);
      }

      await createFeedbackPriorityChangedNotification({
        feedbackId,
        newPriority: priority,
        oldPriority: feedbackThread.priority,
        feedbackOwnerId: feedbackThread.user_id,
        priorityUpdaterId: userId,
      });

      // Invalidate both admin and public caches
      remoteCache.admin.feedback.list.updateTag();
      remoteCache.public.feedback.list.updateTag();
      remoteCache.admin.feedback.threads.byId.updateTag({
        id: feedbackId,
      });
      remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
      remoteCache.public.feedback.recent.updateTag();

      return { priority };
    }
  );

const toggleFeedbackRoadmapSchema = z.object({
  feedbackId: z.string(),
  isInRoadmap: z.boolean(),
});

export const adminToggleFeedbackFromRoadmapAction = adminActionClient
  .inputSchema(toggleFeedbackRoadmapSchema)
  .action(
    async ({ parsedInput: { feedbackId, isInRoadmap }, ctx: { userId } }) => {
      const { error, data: updatedFeedbackData } = await supabaseAdminClient
        .from("marketing_feedback_threads")
        .update({ added_to_roadmap: isInRoadmap })
        .eq("id", feedbackId)
        .single();

      if (error) {
        throw new Error(error.message);
      }

      if (isInRoadmap) {
        await adminToggleFeedbackVisibilityAction({
          feedbackId,
          isPubliclyVisible: true,
        });
      }

      await createFeedbackAddedToRoadmapUpdatedNotification({
        feedbackId,
        isInRoadmap,
        updaterId: userId,
      });

      // Invalidate both admin and public caches
      remoteCache.admin.feedback.list.updateTag();
      remoteCache.public.feedback.list.updateTag();
      remoteCache.admin.feedback.threads.byId.updateTag({
        id: feedbackId,
      });
      remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
      remoteCache.public.feedback.recent.updateTag();
      // Invalidate roadmap caches
      remoteCache.admin.roadmap.items.list.updateTag();
      remoteCache.public.roadmap.items.list.updateTag();
      return updatedFeedbackData;
    }
  );

const toggleFeedbackOpenForCommentsSchema = z.object({
  feedbackId: z.string(),
  isOpenForComments: z.boolean(),
});

export const adminToggleFeedbackOpenForCommentsAction = adminActionClient
  .inputSchema(toggleFeedbackOpenForCommentsSchema)
  .action(
    async ({
      parsedInput: { feedbackId, isOpenForComments },
      ctx: { userId },
    }) => {
      const { error } = await supabaseAdminClient
        .from("marketing_feedback_threads")
        .update({ open_for_public_discussion: isOpenForComments })
        .eq("id", feedbackId);

      if (error) {
        throw new Error(error.message);
      }

      if (isOpenForComments) {
        await adminToggleFeedbackVisibilityAction({
          feedbackId,
          isPubliclyVisible: isOpenForComments,
        });
      }

      await createUpdateFeedbackOpenForCommentsNotification({
        feedbackId,
        isOpenForComments,
        updaterId: userId,
      });

      // Invalidate both admin and public caches
      remoteCache.admin.feedback.list.updateTag();
      remoteCache.public.feedback.list.updateTag();
      remoteCache.admin.feedback.threads.byId.updateTag({
        id: feedbackId,
      });
      remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
      remoteCache.public.feedback.recent.updateTag();

      return { isOpenForComments };
    }
  );

const toggleFeedbackVisibilitySchema = z.object({
  feedbackId: z.string(),
  isPubliclyVisible: z.boolean(),
});

export const adminToggleFeedbackVisibilityAction = adminActionClient
  .inputSchema(toggleFeedbackVisibilitySchema)
  .action(
    async ({
      parsedInput: { feedbackId, isPubliclyVisible },
      ctx: { userId },
    }) => {
      const { error } = await supabaseAdminClient
        .from("marketing_feedback_threads")
        .update({ is_publicly_visible: isPubliclyVisible })
        .eq("id", feedbackId);

      if (error) {
        throw new Error(error.message);
      }

      await createFeedbackVisibilityUpdatedNotification({
        feedbackId,
        isPubliclyVisible,
        updaterId: userId,
      });

      // Invalidate both admin and public caches
      remoteCache.admin.feedback.list.revalidateTag();
      remoteCache.admin.feedback.threads.byId.updateTag({
        id: feedbackId,
      });

      remoteCache.public.feedback.list.revalidateTag();
      remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
      remoteCache.public.feedback.recent.updateTag();

      return { isPubliclyVisible };
    }
  );

export async function getFeedbackStakeholdersExceptMentionedUser({
  feedbackId,
  excludedUserId,
}: {
  feedbackId: string;
  excludedUserId?: string;
}): Promise<string[]> {
  // return all the user ids that are concerned with the feedback conversation including owner
  // except the one mentioned, the mentioned user could be owner of the feedback thread or the commentator or logged in user
  try {
    const supabaseClient = await supabaseClientBasedOnUserRole();

    const feedbackOwnerQuery = supabaseClient
      .from("marketing_feedback_threads")
      .select("user_id")
      .eq("id", feedbackId);
    const feedbackCommentatorsQuery = supabaseClient
      .from("marketing_feedback_comments")
      .select("user_id")
      .eq("thread_id", feedbackId);

    const [feedbackOwnerResult, feedbackCommentatorsResult] = await Promise.all(
      [feedbackOwnerQuery, feedbackCommentatorsQuery]
    );

    if (feedbackOwnerResult.error) throw feedbackOwnerResult.error;
    if (feedbackCommentatorsResult.error)
      throw feedbackCommentatorsResult.error;

    const stakeholders = new Set<string>();

    if (feedbackOwnerResult.data.length > 0) {
      stakeholders.add(feedbackOwnerResult.data[0].user_id);
    }

    feedbackCommentatorsResult.data.forEach((comment) => {
      stakeholders.add(comment.user_id);
    });

    if (excludedUserId) {
      stakeholders.delete(excludedUserId);
    }

    return Array.from(stakeholders);
  } catch (error) {
    throw error;
  }
}

const toggleFeedbackUpvoteSchema = z.object({
  feedbackId: z.string(),
});

export const toggleFeedbackUpvoteAction = authActionClient
  .inputSchema(toggleFeedbackUpvoteSchema)
  .action(async ({ parsedInput: { feedbackId }, ctx: { userId } }) => {
    const supabaseClient = await supabaseClientBasedOnUserRole();

    // Check if user already upvoted
    const { data: existingReaction, error: fetchError } = await supabaseClient
      .from("marketing_feedback_thread_reactions")
      .select("id")
      .eq("thread_id", feedbackId)
      .eq("user_id", userId)
      .eq("reaction_type", "upvote")
      .maybeSingle();

    if (fetchError) {
      throw new Error(fetchError.message);
    }

    if (existingReaction) {
      // Remove upvote
      const { error: deleteError } = await supabaseClient
        .from("marketing_feedback_thread_reactions")
        .delete()
        .eq("id", existingReaction.id);

      if (deleteError) {
        throw new Error(deleteError.message);
      }
    } else {
      // Add upvote
      const { error: insertError } = await supabaseClient
        .from("marketing_feedback_thread_reactions")
        .insert({
          thread_id: feedbackId,
          user_id: userId,
          reaction_type: "upvote",
        });

      if (insertError) {
        throw new Error(insertError.message);
      }
    }

    // Invalidate both admin and public caches
    remoteCache.admin.feedback.list.updateTag();
    remoteCache.public.feedback.list.updateTag();
    remoteCache.admin.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.threads.byId.updateTag({ id: feedbackId });
    remoteCache.public.feedback.recent.updateTag();

    return { success: true, upvoted: !existingReaction };
  });
