"use client";

import { Link } from "@/components/intl-link";
import { useNotificationsContext } from "@/contexts/NotificationsContext";
import { Bell, ExternalLink } from "lucide-react";
import { DropdownMenuItem, DropdownMenuSeparator } from "./ui/dropdown-menu";
import { UnseenNotificationCounterBadge } from "./unseen-notification-counter-badge";

export function NotificationsDropdownMenuTrigger() {
  const { setIsDialogOpen } = useNotificationsContext();
  return (
    <>
      <DropdownMenuItem
        className="flex items-center justify-between gap-2"
        onClick={() => {
          setIsDialogOpen(true);
        }}
      >
        <span className="flex items-center gap-2">
          <Bell />
          Notifications
        </span>
        <UnseenNotificationCounterBadge />
      </DropdownMenuItem>
      <DropdownMenuSeparator className="my-1" />
      <DropdownMenuItem asChild>
        <Link href="/user/notifications" className="flex items-center gap-2">
          <ExternalLink className="h-4 w-4" />
          View all notifications
        </Link>
      </DropdownMenuItem>
    </>
  );
}
