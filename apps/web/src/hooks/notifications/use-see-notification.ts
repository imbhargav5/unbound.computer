"use client";

import { useMutation } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { seeNotification } from "@/data/user/client/notifications";
import { getQueryClient } from "@/lib/query-client";

/**
 * Hook to mark a single notification as seen.
 * Triggers a router refresh on success to update the UI.
 *
 * @returns Mutation object with mutate function accepting a notification ID
 */
export function useSeeNotification() {
  const router = useRouter();
  const queryClient = getQueryClient();

  return useMutation(
    {
      mutationFn: async (notificationId: string) =>
        seeNotification(notificationId),
      onSuccess: () => {
        router.refresh();
      },
    },
    queryClient
  );
}
