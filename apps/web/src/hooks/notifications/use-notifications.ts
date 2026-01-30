"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { useEffect } from "react";
import { getPaginatedNotifications } from "@/data/user/client/notifications";
import { getQueryClient } from "@/lib/query-client";
import type { DBTable } from "@/types";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import { notificationKeys } from "./query-keys";
import { useUnseenNotificationIds } from "./use-unseen-notification-ids";

/**
 * Constant representing the number of notifications to fetch per page.
 */
const NOTIFICATIONS_PAGE_SIZE = 10;

/**
 * Hook to manage paginated notifications for the current user.
 * Automatically refetches when unseen notification IDs change.
 *
 * @returns Object containing notifications, loading state, and pagination controls
 */
export function useNotifications(claims: UserClaimsSchemaType) {
  const userId = claims.sub;
  const { unseenNotificationIds } = useUnseenNotificationIds(claims);
  const queryClient = getQueryClient();

  const {
    data,
    isFetchingNextPage,
    isLoading,
    fetchNextPage,
    hasNextPage,
    refetch,
  } = useInfiniteQuery(
    {
      queryKey: notificationKeys.paginated(userId),
      queryFn: async ({ pageParam }) =>
        getPaginatedNotifications(
          userId,
          pageParam ?? 0,
          NOTIFICATIONS_PAGE_SIZE
        ),
      getNextPageParam: (lastPage, _pages) => {
        const pageNumber = lastPage[0];
        const rows = lastPage[1];

        if (rows.length < NOTIFICATIONS_PAGE_SIZE) return;
        return pageNumber + 1;
      },
      initialPageParam: 0,
      initialData: {
        pageParams: [0],
        pages: [[0, []]],
      },
      refetchOnWindowFocus: false,
    },
    queryClient
  );

  useEffect(() => {
    refetch();
  }, [unseenNotificationIds, refetch]);

  const notifications: DBTable<"user_notifications">[] =
    data?.pages.flatMap((page) => page[1]) ?? [];

  return {
    notifications,
    isFetchingNextPage,
    isLoading,
    fetchNextPage,
    hasNextPage,
    refetch,
  };
}
