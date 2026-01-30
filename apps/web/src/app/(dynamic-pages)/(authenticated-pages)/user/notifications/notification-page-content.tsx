"use client";

import { Check } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { useCallback, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  useNotifications,
  useReadAllNotifications,
} from "@/hooks/notifications";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import { EmptyState } from "./empty-state";
import { NotificationsList } from "./notifications-list";

type FilterTab = "all" | "unread" | "read";

export function NotificationPageContent({
  userClaims,
}: {
  userClaims: UserClaimsSchemaType;
}) {
  const [activeTab, setActiveTab] = useState<FilterTab>("all");
  const {
    notifications,
    hasNextPage,
    fetchNextPage,
    isFetchingNextPage,
    isLoading,
  } = useNotifications(userClaims);
  const { mutate: mutateReadAllNotifications } =
    useReadAllNotifications(userClaims);

  const handleMarkAllAsRead = useCallback(() => {
    mutateReadAllNotifications();
  }, [mutateReadAllNotifications]);

  // Filter notifications based on active tab
  const filteredNotifications = notifications.filter((notification) => {
    if (activeTab === "all") return true;
    if (activeTab === "read") return notification.is_read;
    if (activeTab === "unread") return !notification.is_read;
    return true;
  });

  const unreadCount = notifications.filter((n) => !n.is_read).length;

  return (
    <div className="space-y-6">
      <div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
        <Tabs
          className="w-full sm:w-auto"
          defaultValue="all"
          onValueChange={(value) => setActiveTab(value as FilterTab)}
          value={activeTab}
        >
          <TabsList className="grid w-full grid-cols-3 sm:w-[400px]">
            <TabsTrigger className="flex items-center gap-2" value="all">
              All
              <span className="rounded-full bg-muted px-2 py-0.5 text-xs">
                {notifications.length}
              </span>
            </TabsTrigger>
            <TabsTrigger className="flex items-center gap-2" value="unread">
              Unread
              {unreadCount > 0 && (
                <span className="rounded-full bg-primary px-2 py-0.5 text-primary-foreground text-xs">
                  {unreadCount}
                </span>
              )}
            </TabsTrigger>
            <TabsTrigger value="read">Read</TabsTrigger>
          </TabsList>
        </Tabs>

        {unreadCount > 0 && (
          <Button
            className="flex w-full items-center gap-2 whitespace-nowrap sm:w-auto"
            onClick={handleMarkAllAsRead}
            size="sm"
            variant="outline"
          >
            <Check className="h-4 w-4" />
            Mark all as read
          </Button>
        )}
      </div>

      <div className="relative min-h-[200px]">
        <AnimatePresence mode="wait">
          {isLoading ? (
            <motion.div
              animate={{ opacity: 1 }}
              className="space-y-4"
              exit={{ opacity: 0 }}
              initial={{ opacity: 0 }}
            >
              {Array.from({ length: 3 }).map((_, index) => (
                <Card className="p-4" key={index}>
                  <div className="flex items-start gap-4">
                    <Skeleton className="h-12 w-12 rounded-full" />
                    <div className="flex-1 space-y-2">
                      <Skeleton className="h-4 w-3/4" />
                      <Skeleton className="h-4 w-full" />
                      <Skeleton className="h-3 w-1/4" />
                    </div>
                  </div>
                </Card>
              ))}
            </motion.div>
          ) : filteredNotifications.length === 0 ? (
            <EmptyState />
          ) : (
            <motion.div
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              initial={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
            >
              <NotificationsList
                fetchNextPage={fetchNextPage}
                hasNextPage={hasNextPage}
                isFetchingNextPage={isFetchingNextPage}
                notifications={filteredNotifications}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
