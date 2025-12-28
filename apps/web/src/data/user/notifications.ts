import type { Json } from "database/types";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import type { UserNotificationPayloadType } from "@/utils/zod-schemas/notifications";

export const createNotification = async (
  userId: string,
  payload: UserNotificationPayloadType
) => {
  const supabaseClient = await createSupabaseUserServerActionClient();
  const { data: notification, error } = await supabaseClient
    .from("user_notifications")
    .insert({
      user_id: userId,
      payload,
    });
  if (error) throw error;
  return notification;
};

export async function createMultipleNotifications(
  notifications: Array<{ userId: string; payload: Json }>
) {
  const supabaseClient = await createSupabaseUserServerActionClient();
  const { data: notificationsData, error } = await supabaseClient
    .from("user_notifications")
    .insert(
      notifications.map(({ userId, payload }) => ({
        user_id: userId,
        payload,
      }))
    );

  if (error) throw error;
  return notificationsData;
}

export const createAcceptedWorkspaceInvitationNotification = async (
  userId: string,
  {
    workspaceId,
    workspaceSlug,
    inviteeFullName,
  }: {
    workspaceId: string;
    workspaceSlug: string;
    inviteeFullName: string;
  }
) => {
  const payload: Extract<
    UserNotificationPayloadType,
    {
      type: "acceptedWorkspaceInvitation";
    }
  > = {
    workspaceId,
    type: "acceptedWorkspaceInvitation",
    userFullName: inviteeFullName,
    workspaceSlug,
  };

  return await createNotification(userId, payload);
};

export const createWorkspaceInvitationNotification = async (
  userId: string,
  {
    workspaceId,
    workspaceName,
    inviterFullName,
    invitationId,
  }: {
    workspaceId: string;
    workspaceName: string;
    inviterFullName: string;
    invitationId: string;
  }
) => {
  const payload: Extract<
    UserNotificationPayloadType,
    {
      type: "invitedToWorkspace";
    }
  > = {
    workspaceId,
    workspaceName,
    inviterFullName,
    invitationId,
    type: "invitedToWorkspace",
  };

  return await createNotification(userId, payload);
};

export const getUnseenNotificationIds = async (userId: string) => {
  const supabase = await createSupabaseUserServerComponentClient();
  const { data: notifications, error } = await supabase
    .from("user_notifications")
    .select("id")
    .eq("is_seen", false)
    .eq("user_id", userId);
  if (error) throw error;
  return notifications;
};
