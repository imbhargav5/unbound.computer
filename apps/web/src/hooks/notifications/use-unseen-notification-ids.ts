"use client";

import { useQuery } from "@tanstack/react-query";
import { useEffect } from "react";
import { getUnseenNotificationIds } from "@/data/user/client/notifications";
import { getQueryClient } from "@/lib/query-client";
import { supabaseUserClientComponent } from "@/supabase-clients/user/supabase-user-client-component";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import { notificationKeys } from "./query-keys";

/**
 * Hook to fetch and track unseen notification IDs for the current user.
 * Automatically subscribes to real-time updates via Supabase.
 *
 * @returns Object containing unseen notification IDs and count
 */
export function useUnseenNotificationIds(userClaims: UserClaimsSchemaType) {
  const queryClient = getQueryClient();
  const { data, refetch } = useQuery(
    {
      queryKey: notificationKeys.unseenIds(userClaims.sub),
      queryFn: async () => getUnseenNotificationIds(userClaims.sub),
      initialData: [],
      refetchOnWindowFocus: false,
    },
    queryClient
  );

  useEffect(() => {
    const channelId = `user-notifications:${userClaims.sub}`;
    const channel = supabaseUserClientComponent
      .channel(channelId)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "user_notifications",
          filter: `user_id=eq.${userClaims.sub}`,
        },
        () => {
          refetch();
        }
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "user_notifications",
          filter: `user_id=eq.${userClaims.sub}`,
        },
        () => {
          refetch();
        }
      )
      .subscribe();

    return () => {
      channel.unsubscribe();
    };
  }, [refetch, userClaims.sub]);

  return {
    unseenNotificationIds: data,
    unseenNotificationCount: data.length,
  };
}
