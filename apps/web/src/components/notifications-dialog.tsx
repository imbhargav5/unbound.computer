"use client";

import { Check, ExternalLink } from "lucide-react";
import moment from "moment";
import { AnimatePresence, motion } from "motion/react";
import { useCallback } from "react";
import { toast } from "sonner";
import { Link } from "@/components/intl-link";
import { Skeleton } from "@/components/ui/skeleton";
import {
  useNotifications,
  useNotificationsDialog,
  useReadAllNotifications,
  useSeeNotification,
  useUnseenNotificationIds,
} from "@/hooks/notifications";
import type { DBTable } from "@/types";
import { parseNotification } from "@/utils/parse-notification";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import { NotificationItem } from "./notification-item";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "./ui/dialog";

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

  const { mutate: mutateSeeNotification } = useSeeNotification();

  return (
    <motion.div
      animate={{ opacity: 1, y: 0 }}
      className="grid grid-cols-1 divide-y"
      exit={{ opacity: 0, y: -10 }}
      initial={{ opacity: 0, y: 10 }}
      transition={{ duration: 0.2 }}
    >
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
    </motion.div>
  );
}

export const NotificationsDialog = ({
  userClaims,
}: {
  userClaims: UserClaimsSchemaType;
}) => {
  const { unseenNotificationIds } = useUnseenNotificationIds(userClaims);
  const { mutate: mutateReadAllNotifications } =
    useReadAllNotifications(userClaims);
  const {
    notifications,
    hasNextPage,
    fetchNextPage,
    isFetchingNextPage,
    isLoading,
  } = useNotifications(userClaims);
  const { isOpen: isDialogOpen, setIsOpen: setIsDialogOpen } =
    useNotificationsDialog();

  return (
    <Dialog onOpenChange={setIsDialogOpen} open={isDialogOpen}>
      <DialogContent className="hide-dialog-close w-full overflow-hidden rounded-xl md:w-[560px]">
        <DialogHeader>
          <div className="flex items-center justify-between">
            <DialogTitle>Notifications</DialogTitle>
            <div className="flex items-center gap-2">
              {unseenNotificationIds?.length > 0 && (
                <motion.button
                  className="flex items-center text-muted-foreground text-sm transition-colors hover:text-foreground"
                  onClick={() => mutateReadAllNotifications()}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                >
                  <Check className="mr-1 h-4 w-4" />
                  Mark all as read
                </motion.button>
              )}
              <Link
                className="flex items-center text-muted-foreground text-sm transition-colors hover:text-foreground"
                href="/user/notifications"
              >
                <ExternalLink className="mr-1 h-4 w-4" />
                View all
              </Link>
            </div>
          </div>
        </DialogHeader>
        <div className="max-h-[400px] overflow-y-auto">
          <AnimatePresence>
            {isLoading ? (
              <motion.div
                animate={{ opacity: 1 }}
                className="p-4"
                exit={{ opacity: 0 }}
                initial={{ opacity: 0 }}
              >
                <Skeleton className="mb-2 h-16" />
                <Skeleton className="mb-2 h-16" />
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
                animate={{ opacity: 1 }}
                className="p-4 text-center text-muted-foreground"
                exit={{ opacity: 0 }}
                initial={{ opacity: 0 }}
              >
                No notifications yet.
              </motion.div>
            )}
          </AnimatePresence>
          {hasNextPage && (
            <motion.div
              animate={{ opacity: 1 }}
              className="p-4 text-center"
              exit={{ opacity: 0 }}
              initial={{ opacity: 0 }}
            >
              {isFetchingNextPage ? (
                <Skeleton className="mx-auto h-8 w-24" />
              ) : (
                <button
                  className="text-muted-foreground text-sm transition-colors hover:text-foreground"
                  onClick={() => fetchNextPage()}
                >
                  Load more
                </button>
              )}
            </motion.div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
};
