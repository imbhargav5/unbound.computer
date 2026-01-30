"use client";

import { useUnseenNotificationIds } from "@/hooks/notifications";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";
import { Badge } from "./ui/badge";

export function UnseenNotificationCounterBadge({
  userClaims,
}: {
  userClaims: UserClaimsSchemaType;
}) {
  const { unseenNotificationCount } = useUnseenNotificationIds(userClaims);
  if (unseenNotificationCount === 0) {
    return null;
  }
  return <Badge variant="destructive">{unseenNotificationCount}</Badge>;
}
