"use client";

import { useSearchParams } from "next/navigation";
import { useCallback } from "react";
import { usePathname, useRouter } from "@/i18n/navigation";

/**
 * Hook to manage the open/close state of the mobile menu.
 * Uses URL search params to sync state across components without context.
 */
export function useMobileMenu() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const isOpen = searchParams.get("mobile-menu") === "open";

  const setIsOpen = useCallback(
    (open: boolean) => {
      const params = new URLSearchParams(searchParams.toString());
      if (open) {
        params.set("mobile-menu", "open");
      } else {
        params.delete("mobile-menu");
      }
      router.push(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams]
  );

  const toggle = useCallback(() => setIsOpen(!isOpen), [setIsOpen, isOpen]);
  const close = useCallback(() => setIsOpen(false), [setIsOpen]);

  return {
    isOpen,
    setIsOpen,
    toggle,
    close,
  };
}
