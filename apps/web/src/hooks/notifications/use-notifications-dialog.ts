"use client";

import { useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { usePathname, useRouter } from "@/i18n/navigation";

const NOTIFICATIONS_DIALOG_SEARCH_PARAM = "showNotificationsDialog";

/**
 * Hook to manage the open/close state of the notifications dialog.
 * Uses URL search params to sync state across components without context.
 *
 * @returns Object with isOpen state and setIsOpen setter
 */
export function useNotificationsDialog() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const isOpen = searchParams.get(NOTIFICATIONS_DIALOG_SEARCH_PARAM) === "open";

  const setIsOpen = useCallback(
    (open: boolean) => {
      const params = new URLSearchParams(searchParams.toString());
      if (open) {
        params.set(NOTIFICATIONS_DIALOG_SEARCH_PARAM, "open");
      } else {
        params.delete(NOTIFICATIONS_DIALOG_SEARCH_PARAM);
      }
      router.push(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams]
  );

  return {
    isOpen,
    setIsOpen,
  };
}
