"use client";

import { NotificationItem } from "@/components/NavigationMenu/NotificationItem";
import { T } from "@/components/ui/Typography";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { useNotificationsContext } from "@/contexts/NotificationsContext";
import type { DBTable } from "@/types";
import { parseNotification } from "@/utils/parseNotification";
import { AnimatePresence, motion } from "framer-motion";
import { Bell, Check } from "lucide-react";
import moment from "moment";
import { useCallback, useEffect } from "react";
import { toast } from "sonner";
import { Skeleton } from "../ui/skeleton";

function Notification({
  notification,
}: {
  notification: DBTable<"user_notifications">;
}) {
  const notificationPayload = parseNotification(notification.payload);
  const handleNotificationClick = useCallback(() => {
    if (notificationPayload.type === "welcome") {
      toast("Welcome to Nextbase");
    }
  }, [notificationPayload]);

  const { mutateSeeNotification } = useNotificationsContext();

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
          notificationPayload.actionType === "link"
            ? notificationPayload.href
            : undefined
        }
        onClick={
          notificationPayload.actionType === "button"
            ? handleNotificationClick
            : undefined
        }
        image={notificationPayload.image}
        isRead={notification.is_read}
        isNew={!notification.is_seen}
        notificationId={notification.id}
        onHover={() => {
          if (!notification.is_seen) {
            mutateSeeNotification(notification.id);
          }
        }}
      />
    </motion.div>
  );
}

export const Notifications = () => {
  const {
    unseenNotificationIds,
    mutateReadAllNotifications,

    notifications,
    hasNextPage,
    fetchNextPage,
    isFetchingNextPage,
    isLoading,
    refetch,
  } = useNotificationsContext();

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
          <div className="px-6 py-3 border-b">
            {" "}
            {/* Reduced padding here */}
            <div className="flex justify-between items-center">
              <T.H3 className="text-foreground text-lg !mt-0">
                {" "}
                {/* Reduced text size */}Notifications
              </T.H3>
              {unseenNotificationIds?.length > 0 && (
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => mutateReadAllNotifications()}
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
                  <Notification
                    key={notification.id}
                    notification={notification}
                  />
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
