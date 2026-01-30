/**
 * Centralized query key factory for notification-related queries.
 * This ensures consistent query key structure across all notification hooks.
 */
export const notificationKeys = {
  all: ["notifications"] as const,
  unseenIds: (userId: string) =>
    [...notificationKeys.all, "unseen-ids", userId] as const,
  paginated: (userId: string) =>
    [...notificationKeys.all, "paginated", userId] as const,
};
