"use client";

import { useMutation } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { readNotification } from "@/data/user/client/notifications";
import { getQueryClient } from "@/lib/query-client";

/**
 * Hook to mark a single notification as read.
 * Triggers a router refresh on success to update the UI.
 *
 * @returns Mutation object with mutate function accepting a notification ID
 */
export function useReadNotification() {
  const router = useRouter();
  const queryClient = getQueryClient();

  return useMutation(
    {
      mutationFn: async (notificationId: string) =>
        readNotification(notificationId),
      onSuccess: () => {
        router.refresh();
      },
    },
    queryClient
  );
}
