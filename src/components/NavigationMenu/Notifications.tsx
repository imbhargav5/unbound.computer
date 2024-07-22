'use client';

import { NotificationItem } from '@/components/NavigationMenu/NotificationItem';
import { T } from '@/components/ui/Typography';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import { useSAToastMutation } from '@/hooks/useSAToastMutation';
import { supabaseUserClientComponentClient } from '@/supabase-clients/user/supabaseUserClientComponentClient';
import type { Table } from '@/types';
import { parseNotification } from '@/utils/parseNotification';
import { useInfiniteQuery, useMutation, useQuery } from '@tanstack/react-query';
import { AnimatePresence, motion } from 'framer-motion';
import { Bell, Check } from 'lucide-react';
import moment from 'moment';
import { useRouter } from 'next/navigation';
import { useCallback, useEffect } from 'react';
import { useDidMount } from 'rooks';
import { toast } from 'sonner';
import { Skeleton } from '../ui/skeleton';
import {
  getPaginatedNotifications,
  getUnseenNotificationIds,
  readAllNotifications,
  seeNotification
} from './fetchClientNotifications';

const NOTIFICATIONS_PAGE_SIZE = 10;
const useUnseenNotificationIds = (userId: string) => {
  const { data, refetch } = useQuery(
    ['unseen-notification-ids', userId],
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
    const channel = supabaseUserClientComponentClient
      .channel(channelId)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'user_notifications',
          filter: 'user_id=eq.' + userId,
        },
        () => {
          refetch();
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'user_notifications',
          filter: 'user_id=eq.' + userId,
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
  const { data, isFetchingNextPage, isLoading, fetchNextPage, hasNextPage, refetch } =
    useInfiniteQuery(
      ['paginatedNotifications', userId],
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

function NextPageLoader({ onMount }: { onMount: () => void }) {
  useDidMount(() => {
    onMount();
  });
  return <div className="h-4"></div>;
}

export const useReadAllNotifications = (userId: string) => {
  const router = useRouter();
  return useSAToastMutation(
    async () => {
      return readAllNotifications(userId);
    },
    {
      loadingMessage: 'Marking all notifications as read...',
      successMessage: 'All notifications marked as read',
      errorMessage(error) {
        try {
          if (error instanceof Error) {
            return String(error.message);
          }
          return `Failed to mark all notifications as read ${String(error)}`;
        } catch (_err) {
          console.warn(_err);
          return 'Failed to mark all notifications as read';
        }
      },
      onSuccess: () => {
        router.refresh();
      },
    },
  );
};



function Notification({
  notification,
}: {
  notification: Table<'user_notifications'>;
}) {
  const router = useRouter();
  const notificationPayload = parseNotification(notification.payload);
  const handleNotificationClick = useCallback(() => {
    if (notificationPayload.type === 'welcome') {
      toast('Welcome to Nextbase');
    }
  }, [notificationPayload]);

  const { mutate: mutateSeeMutation } = useMutation(
    async () => await seeNotification(notification.id),
    {
      onSuccess: () => router.refresh(),
    }
  );

  return (
    <motion.div
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ duration: 0.2 }}
    >
      <NotificationItem
        key={notification.id}
        title={notificationPayload.title}
        description={notificationPayload.description}
        createdAt={moment(notification.created_at).fromNow()}
        href={
          notificationPayload.actionType === 'link'
            ? notificationPayload.href
            : undefined
        }
        onClick={
          notificationPayload.actionType === 'button'
            ? handleNotificationClick
            : undefined
        }
        image={notificationPayload.image}
        isRead={notification.is_read}
        isNew={!notification.is_seen}
        notificationId={notification.id}
        onHover={() => {
          if (!notification.is_seen) {
            mutateSeeMutation();
          }
        }}
      />
    </motion.div>
  );
}

export const Notifications = ({ userId }: { userId: string }) => {
  const unseenNotificationIds = useUnseenNotificationIds(userId);
  const {
    notifications,
    hasNextPage,
    fetchNextPage,
    isFetchingNextPage,
    isLoading,
    refetch,
  } = useNotifications(userId);
  const { mutate } = useReadAllNotifications(userId);

  useEffect(() => {
    refetch();
  }, [unseenNotificationIds, refetch]);

  return (
    <Popover>
      <PopoverTrigger className="relative focus:outline-none">
        <motion.div whileHover={{ scale: 1.05 }} whileTap={{ scale: 0.95 }}>
          <Bell className="w-5 h-5 text-muted-foreground hover:text-foreground transition-colors" />
          <AnimatePresence>
            {unseenNotificationIds?.length > 0 && (
              <motion.span
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                exit={{ scale: 0 }}
                className="absolute -top-1.5 -right-2 bg-red-500 px-1.5 rounded-full font-bold text-white text-xs"
              >
                {unseenNotificationIds.length}
              </motion.span>
            )}
          </AnimatePresence>
        </motion.div>
      </PopoverTrigger>
      <PopoverContent className="w-[560px] p-0 rounded-xl overflow-hidden mr-12">
        <div className="bg-background shadow-lg">
          <div className="px-6 py-3 border-b"> {/* Reduced padding here */}
            <div className="flex justify-between items-center">
              <T.H3 className="text-foreground text-lg !mt-0"> {/* Reduced text size */}Notifications</T.H3>
              {unseenNotificationIds?.length > 0 && (
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => mutate()}
                  className="flex items-center text-sm text-muted-foreground hover:text-foreground transition-colors"
                >
                  <Check className="w-4 h-4 mr-1" />
                  Mark all as read
                </motion.button>
              )}
            </div>
          </div>
          <div className="max-h-[400px] overflow-y-auto">
            <AnimatePresence>
              {isLoading ? (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="p-4"
                >
                  <Skeleton className="h-16 mb-2" />
                  <Skeleton className="h-16 mb-2" />
                  <Skeleton className="h-16" />
                </motion.div>
              ) : notifications?.length > 0 ? (
                notifications.map((notification) => (
                  <Notification key={notification.id} notification={notification} />
                ))
              ) : (
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="p-4 text-center text-muted-foreground"
                >
                  No notifications yet.
                </motion.div>
              )}
            </AnimatePresence>
            {hasNextPage && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="p-4 text-center"
              >
                {isFetchingNextPage ? (
                  <Skeleton className="h-8 w-24 mx-auto" />
                ) : (
                  <button
                    onClick={() => fetchNextPage()}
                    className="text-sm text-muted-foreground hover:text-foreground transition-colors"
                  >
                    Load more
                  </button>
                )}
              </motion.div>
            )}
          </div>
        </div>
      </PopoverContent>
    </Popover>
  );
};
