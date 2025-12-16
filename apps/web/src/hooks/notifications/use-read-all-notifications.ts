"use client";

import { useMutation } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { readAllNotifications } from "@/data/user/client/notifications";
import { getQueryClient } from "@/lib/query-client";
import type { UserClaimsSchemaType } from "@/utils/zod-schemas/user-claims-schema";

/**
 * Hook to mark all notifications as read for the current user.
 * Displays toast notifications for loading, success, and error states.
 *
 * @returns Mutation object with mutate function to mark all notifications as read
 */
export function useReadAllNotifications(userClaims: UserClaimsSchemaType) {
  const router = useRouter();
  const queryClient = getQueryClient();

  return useMutation(
    {
      mutationFn: async () => readAllNotifications(userClaims.sub),
      onMutate: () => {
        const toastId = toast.loading("Marking all notifications as read...");
        return { toastId };
      },
      onSuccess: (_, __, context) => {
        if (context?.toastId) {
          toast.dismiss(context.toastId);
          toast.success("All notifications marked as read", {
            id: context.toastId,
          });
        }
        router.refresh();
      },
      onError: (error, __, context) => {
        if (context?.toastId) {
          toast.dismiss(context.toastId);
          try {
            if (error instanceof Error) {
              toast.error(String(error.message), { id: context.toastId });
            } else {
              toast.error(
                `Failed to mark all notifications as read ${String(error)}`,
                { id: context.toastId }
              );
            }
          } catch (_err) {
            console.warn(_err);
            toast.error("Failed to mark all notifications as read", {
              id: context.toastId,
            });
          }
        }
      },
    },
    queryClient
  );
}
