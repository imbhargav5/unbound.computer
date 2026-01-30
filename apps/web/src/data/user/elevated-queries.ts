/**
 * [WARNING: USE SPARINGLY AND ONLY WHEN NECESSARY]
 * These are queries that are selectively run as application admin for convenience.
 * Another option is to harden RLS policies even further for these scenarios. But the drawback
 * is that all those policies which contain select queries across other tables have the tendency to make the
 * queries slower to run. So, we have to be careful about the trade-offs.
 * Use this sparingly and only when necessary and in exceptional scenarios.
 * */
"use server";

import type { UserAppMetadata } from "@supabase/supabase-js";
import type { Json } from "database/types";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { remoteCache } from "@/typed-cache-tags";

/**
 * [Elevated Query]
 * create notification for all admins
 * Reason: A user is not able to view the list of all admins. Hence, we run this query as application admin.
 * This function is called createAdminNotificationForUserActivity because
 * it is used to notify admins when a logged in user performs an activity.
 * */

/**
 * Creates notifications for all admins when a user performs an activity.
 *
 * @param payload - JSON object containing notification data.
 * @param excludedAdminUserId - (Optional) ID of the admin user to exclude from receiving the notification.
 * @returns Returns a Promise resolving to the notification data.
 */
export const createAdminNotification = async ({
  payload,
  excludedAdminUserId,
}: {
  payload: Json;
  excludedAdminUserId?: string;
}) => {
  async function getAllAdminUserIds() {
    const { data, error } = await supabaseAdminClient
      .from("user_roles")
      .select("user_id")
      .eq("role", "admin");

    if (error) {
      throw error;
    }

    return data.map((row) => row.user_id);
  }
  let adminUserIdsToNotify = await getAllAdminUserIds();

  if (
    excludedAdminUserId &&
    adminUserIdsToNotify.includes(excludedAdminUserId)
  ) {
    adminUserIdsToNotify = adminUserIdsToNotify?.filter(
      (userId) => userId != excludedAdminUserId
    );
  }

  const { data: notification, error } = await supabaseAdminClient
    .from("user_notifications")
    .insert(
      adminUserIdsToNotify.map((userId) => ({
        user_id: userId,
        payload,
      }))
    );
  if (error) throw error;
  return notification;
};

/**
 * [Elevated Query]
 * Reason: The user details are not visible to anonymous viewers by default.
 * Get user full name and avatar url for anonymous viewers
 * @param userId
 * @returns user full name and avatar url
 */
export const anonGetUserProfile = async (userId: string) => {
  "use cache: remote";
  remoteCache.public.user.profile.detail.byId.cacheTag({ id: userId });
  const { data, error } = await supabaseAdminClient
    .from("user_profiles")
    .select("*")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

/**
 * [Elevated Query]
 * Update user app metadata
 * Reason: This can only be done using supabaseAdminClient
 */
export const updateUserAppMetadata = async ({
  userId,
  appMetadata,
}: {
  userId: string;
  appMetadata: UserAppMetadata;
}) => {
  const { data, error } = await supabaseAdminClient.auth.admin.updateUserById(
    userId,
    { user_metadata: appMetadata }
  );
  if (error) {
    throw error;
  }
  return data;
};
