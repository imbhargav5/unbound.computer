"use client";

import { Loader2 } from "lucide-react";
import moment from "moment";
import { AnimatePresence, motion } from "motion/react";
import { useCallback, useEffect } from "react";
import { toast } from "sonner";
import { NotificationItem } from "@/components/notification-item";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { useReadNotification, useSeeNotification } from "@/hooks/notifications";
import type { DBTable } from "@/types";
import { parseNotification } from "@/utils/parse-notification";

interface NotificationsListProps {
  notifications: DBTable<"user_notifications">[];
  hasNextPage: boolean | undefined;
  fetchNextPage: () => void;
  isFetchingNextPage: boolean;
}

export function NotificationsList({
  notifications,
  hasNextPage,
  fetchNextPage,
  isFetchingNextPage,
}: NotificationsListProps) {
  const { mutate: mutateSeeNotification } = useSeeNotification();

  // Automatically mark notifications as seen when they come into view
  useEffect(() => {
    const unseenNotifications = notifications.filter((n) => !n.is_seen);
    if (unseenNotifications.length > 0) {
      unseenNotifications.forEach((notification) => {
        mutateSeeNotification(notification.id);
      });
    }
  }, [notifications, mutateSeeNotification]);

  return (
    <motion.div
      animate={{ opacity: 1 }}
      className="space-y-3"
      exit={{ opacity: 0 }}
      initial={{ opacity: 0 }}
    >
      <AnimatePresence initial={false}>
        {notifications.map((notification, index) => (
          <motion.div
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            initial={{ opacity: 0, y: 20 }}
            key={notification.id}
            transition={{ duration: 0.2, delay: index * 0.05 }}
          >
            <Card className="overflow-hidden">
              <Notification notification={notification} />
            </Card>
          </motion.div>
        ))}
      </AnimatePresence>

      {hasNextPage && (
        <div className="flex justify-center pt-6">
          <Button
            className="w-full max-w-md"
            disabled={isFetchingNextPage}
            onClick={() => fetchNextPage()}
            variant="outline"
          >
            {isFetchingNextPage ? (
              <div className="flex items-center gap-2">
                <Loader2 className="h-4 w-4 animate-spin" />
                Loading more notifications...
              </div>
            ) : (
              "Load more notifications"
            )}
          </Button>
        </div>
      )}
    </motion.div>
  );
}

function Notification({
  notification,
}: {
  notification: DBTable<"user_notifications">;
}) {
  const notificationPayload = parseNotification(notification.payload);
  const { mutate: mutateSeeNotification } = useSeeNotification();
  const { mutate: mutateReadNotification } = useReadNotification();

  const handleNotificationClick = useCallback(() => {
    // First mark as read if not already read
    if (!notification.is_read) {
      mutateReadNotification(notification.id);
    }

    // Then handle specific notification actions
    if (notificationPayload.type === "welcome") {
      toast("Welcome to Nextbase");
    }
    // Add more notification type handlers here as needed
  }, [
    notification.id,
    notification.is_read,
    notificationPayload.type,
    mutateReadNotification,
  ]);

  return (
    <NotificationItem
      createdAt={moment(notification.created_at).fromNow()}
      description={notificationPayload.description}
      href={
        notificationPayload.actionType === "link"
          ? notificationPayload.href
          : undefined
      }
      icon={notificationPayload.icon}
      image={notificationPayload.image}
      isNew={!notification.is_seen}
      isRead={notification.is_read}
      key={notification.id}
      notificationId={notification.id}
      onClick={
        notificationPayload.actionType === "button"
          ? handleNotificationClick
          : undefined
      }
      onHover={() => {
        if (!notification.is_seen) {
          mutateSeeNotification(notification.id);
        }
      }}
      title={notificationPayload.title}
    />
  );
}
