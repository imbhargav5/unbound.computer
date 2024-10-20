"use client";

import { createContext, ReactNode, useContext, useEffect } from "react";

import {
  getPaginatedNotifications,
  getUnseenNotificationIds,
  readAllNotifications,
  readNotification,
  seeNotification,
} from "@/data/user/client/notifications";
import { useLoggedInUser } from "@/hooks/useLoggedInUser";
import { useSAToastMutation } from "@/hooks/useSAToastMutation";
import { supabaseUserClientComponent } from "@/supabase-clients/user/supabaseUserClientComponent";
import type { DBTable } from "@/types";
import { useInfiniteQuery, useMutation, useQuery } from "@tanstack/react-query";
import { useRouter } from "next/navigation";

const NOTIFICATIONS_PAGE_SIZE = 10;
const useUnseenNotificationIds = (userId: string) => {
  const { data, refetch } = useQuery(
    ["unseen-notification-ids", userId],
    async () => {
      return getUnseenNotificationIds(userId);
    },
    {
      initialData: [],
      refetchOnWindowFocus: false,
    },
  );
  useEffect(() => {
    const channelId = `user-notifications:${userId}`;
    const channel = supabaseUserClientComponent
      .channel(channelId)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "user_notifications",
          filter: "user_id=eq." + userId,
        },
        () => {
          refetch();
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "user_notifications",
          filter: "user_id=eq." + userId,
        },
        (payload) => {
          refetch();
        },
      )
      .subscribe();

    return () => {
      channel.unsubscribe();
    };
  }, [refetch, userId]);

  return data ?? 0;
};

export const useNotifications = (userId: string) => {
  const {
    data,
    isFetchingNextPage,
    isLoading,
    fetchNextPage,
    hasNextPage,
    refetch,
  } = useInfiniteQuery(
    ["paginatedNotifications", userId],
    async ({ pageParam }) => {
      return getPaginatedNotifications(
        userId,
        pageParam ?? 0,
        NOTIFICATIONS_PAGE_SIZE,
      );
    },
    {
      getNextPageParam: (lastPage, _pages) => {
        const pageNumber = lastPage[0];
        const rows = lastPage[1];

        if (rows.length < NOTIFICATIONS_PAGE_SIZE) return undefined;
        return pageNumber + 1;
      },
      initialData: {
        pageParams: [0],
        pages: [[0, []]],
      },
      // You can disable it here
      refetchOnWindowFocus: false,
    },
  );

  const notifications = data?.pages.flatMap((page) => page[1]) ?? [];
  return {
    notifications,
    isFetchingNextPage,
    isLoading,
    fetchNextPage,
    hasNextPage,
    refetch,
  };
};

const useReadAllNotifications = (userId: string) => {
  const router = useRouter();
  return useSAToastMutation(
    async () => {
      return readAllNotifications(userId);
    },
    {
      loadingMessage: "Marking all notifications as read...",
      successMessage: "All notifications marked as read",
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to mark all notifications as read ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return "Failed to mark all notifications as read";
        }
      },
      onSuccess: () => {
        router.refresh();
      },
    },
  );
};

type NotificationsContextType = {
  unseenNotificationIds: Array<{
    id: string;
  }>;
  notifications: DBTable<"user_notifications">[];
  hasNextPage: boolean | undefined;
  fetchNextPage: () => void;
  isFetchingNextPage: boolean;
  isLoading: boolean;
  refetch: () => void;
  mutateReadAllNotifications: () => void;
  mutateSeeNotification: (notificationId: string) => void;
  mutateReadNotification: (notificationId: string) => void;
};

const NotificationsContext = createContext<NotificationsContextType>(
  {} as NotificationsContextType,
);

export const NotificationsProvider = ({
  children,
}: {
  children: ReactNode;
}) => {
  const user = useLoggedInUser();
  const userId = user.id;
  const unseenNotificationIds = useUnseenNotificationIds(userId);
  const {
    notifications,
    hasNextPage,
    fetchNextPage,
    isFetchingNextPage,
    isLoading,
    refetch,
  } = useNotifications(userId);
  const { mutate: mutateReadAllNotifications } =
    useReadAllNotifications(userId);
  const router = useRouter();
  const { mutate: mutateSeeNotification } = useMutation(
    async (notificationId: string) => await seeNotification(notificationId),
    {
      onSuccess: () => router.refresh(),
    },
  );

  const { mutate: mutateReadNotification } = useMutation(
    async (notificationId: string) => await readNotification(notificationId),
    {
      onSuccess: () => router.refresh(),
    },
  );

  useEffect(() => {
    refetch();
  }, [unseenNotificationIds, refetch]);

  return (
    <NotificationsContext.Provider
      value={{
        unseenNotificationIds,
        notifications,
        hasNextPage,
        fetchNextPage,
        isFetchingNextPage,
        isLoading,
        refetch,
        mutateReadAllNotifications,
        mutateSeeNotification,
        mutateReadNotification,
      }}
    >
      {children}
    </NotificationsContext.Provider>
  );
};

export function useNotificationsContext() {
  const context = useContext(NotificationsContext);
  if (context === undefined) {
    throw new Error(
      "useNotificationsContext must be used within a NotificationsProvider",
    );
  }
  return context;
}
