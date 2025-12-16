"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useAction } from "next-cool-action/hooks";
import { useCallback, useRef } from "react";
import { useTimeoutWhen } from "rooks";
import { toast } from "sonner";
import { createWorkspaceAction } from "@/data/user/workspaces";

/**
 * Hook to manage the open/close state of the create workspace dialog.
 * Uses URL search params to sync state across components without context.
 */
export function useCreateWorkspaceDialog() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const isOpen = searchParams.get("create-workspace") === "open";

  const setIsOpen = useCallback(
    (open: boolean) => {
      const params = new URLSearchParams(searchParams.toString());
      if (open) {
        params.set("create-workspace", "open");
      } else {
        params.delete("create-workspace");
      }
      router.push(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [router, pathname, searchParams]
  );

  const openDialog = useCallback(() => setIsOpen(true), [setIsOpen]);
  const closeDialog = useCallback(() => setIsOpen(false), [setIsOpen]);
  const toggleDialog = useCallback(
    () => setIsOpen(!isOpen),
    [setIsOpen, isOpen]
  );

  const toastRef = useRef<string | number | undefined>(undefined);

  const createWorkspaceActionHelpers = useAction(createWorkspaceAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Creating workspace...", {
        description: "Please wait while we create your workspace.",
      });
    },
    onNavigation: () => {
      toast.success("Workspace created!", { id: toastRef.current });
      toastRef.current = undefined;
    },
    onError: (error) => {
      toast.error("Failed to create workspace.", {
        description: String(error),
        id: toastRef.current,
      });
      toastRef.current = undefined;
    },
  });

  useTimeoutWhen(
    () => {
      createWorkspaceActionHelpers.reset();
      closeDialog();
    },
    // 0 doesn't seem to work here.
    500,
    createWorkspaceActionHelpers.hasNavigated
  );

  return {
    isOpen,
    openDialog,
    closeDialog,
    toggleDialog,
    createWorkspaceActionHelpers,
  };
}
