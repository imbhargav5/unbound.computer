"use client";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useNotificationsContext } from "@/contexts/NotificationsContext";
import { Check } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { useCallback, useState } from "react";
import { EmptyState } from "./EmptyState";
import { NotificationsList } from "./NotificationsList";

type FilterTab = "all" | "unread" | "read";

export function NotificationPageContent() {
  const [activeTab, setActiveTab] = useState<FilterTab>("all");
  const {
    notifications,
    hasNextPage,
    fetchNextPage,
    isFetchingNextPage,
    isLoading,
    mutateReadAllNotifications,
  } = useNotificationsContext();

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
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <Tabs
          defaultValue="all"
          value={activeTab}
          onValueChange={(value) => setActiveTab(value as FilterTab)}
          className="w-full sm:w-auto"
        >
          <TabsList className="grid w-full sm:w-[400px] grid-cols-3">
            <TabsTrigger value="all" className="flex items-center gap-2">
              All
              <span className="text-xs bg-muted px-2 py-0.5 rounded-full">
                {notifications.length}
              </span>
            </TabsTrigger>
            <TabsTrigger value="unread" className="flex items-center gap-2">
              Unread
              {unreadCount > 0 && (
                <span className="text-xs bg-primary text-primary-foreground px-2 py-0.5 rounded-full">
                  {unreadCount}
                </span>
              )}
            </TabsTrigger>
            <TabsTrigger value="read">Read</TabsTrigger>
          </TabsList>
        </Tabs>

        {unreadCount > 0 && (
          <Button
            variant="outline"
            size="sm"
            onClick={handleMarkAllAsRead}
            className="flex items-center gap-2 whitespace-nowrap w-full sm:w-auto"
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
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="space-y-4"
            >
              {Array.from({ length: 3 }).map((_, index) => (
                <Card key={index} className="p-4">
                  <div className="flex items-start gap-4">
                    <Skeleton className="h-12 w-12 rounded-full" />
                    <div className="space-y-2 flex-1">
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
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2 }}
            >
              <NotificationsList
                notifications={filteredNotifications}
                hasNextPage={hasNextPage}
                fetchNextPage={fetchNextPage}
                isFetchingNextPage={isFetchingNextPage}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
