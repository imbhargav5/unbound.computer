"use client";

import { Bell, ExternalLink } from "lucide-react";
import { Link } from "@/components/intl-link";
import { useNotificationsDialog } from "@/hooks/notifications";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import { DropdownMenuItem, DropdownMenuSeparator } from "./ui/dropdown-menu";
import { UnseenNotificationCounterBadge } from "./unseen-notification-counter-badge";

export function NotificationsDropdownMenuTrigger({
  userClaims,
}: {
  userClaims: UserClaimsSchemaType;
}) {
  const { setIsOpen: setIsDialogOpen } = useNotificationsDialog();
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
        <UnseenNotificationCounterBadge userClaims={userClaims} />
      </DropdownMenuItem>
      <DropdownMenuSeparator className="my-1" />
      <DropdownMenuItem asChild>
        <Link className="flex items-center gap-2" href="/user/notifications">
          <ExternalLink className="h-4 w-4" />
          View all notifications
        </Link>
      </DropdownMenuItem>
    </>
  );
}
