"use client";

import { useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { usePathname, useRouter } from "@/i18n/navigation";

const LOCALE_SWITCHER_PARAM = "locale-switcher";

/**
 * Hook to manage the open/close state of the locale switcher dialog.
 * Uses URL search params to sync state across components without context.
 */
export function useLocaleSwitcherDialog() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const isOpen = searchParams.get(LOCALE_SWITCHER_PARAM) === "open";

  const setIsOpen = useCallback(
    (open: boolean) => {
      const params = new URLSearchParams(searchParams.toString());
      if (open) {
        params.set(LOCALE_SWITCHER_PARAM, "open");
      } else {
        params.delete(LOCALE_SWITCHER_PARAM);
      }
      router.push(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams]
  );

  const open = useCallback(() => setIsOpen(true), [setIsOpen]);
  const close = useCallback(() => setIsOpen(false), [setIsOpen]);

  return {
    isOpen,
    setIsOpen,
    open,
    close,
  };
}
