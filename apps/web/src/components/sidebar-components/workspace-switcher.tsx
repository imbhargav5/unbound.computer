"use client";

import { ChevronsUpDown, Home, Plus } from "lucide-react";
import { Fragment } from "react";
import { toast } from "sonner";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuShortcut,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { useCreateWorkspaceDialog } from "@/hooks/use-create-workspace-dialog";
import { useSafeShortcut } from "@/hooks/use-safe-shortcut";
import { useRouter } from "@/i18n/navigation";
import type { SlimWorkspace, SlimWorkspaces } from "@/types";
import { getWorkspaceSubPath } from "@/utils/workspaces";

function WorkspaceToggler({
  workspace,
  index,
  currentWorkspaceId,
  goToWorkspace,
}: {
  workspace: SlimWorkspace;
  index: number;
  currentWorkspaceId: string;
  goToWorkspace: (workspace: SlimWorkspace) => void;
}) {
  // Only register shortcuts for first 9 workspaces (⌘1-⌘9)
  // Keyboards don't have Digit10+, so shortcuts above 9 don't work
  if (index >= 9) {
    return null;
  }

  const shortcutNumber = index + 1;
  const shortcutCode = `Digit${shortcutNumber}`;
  useSafeShortcut(shortcutCode, (event) => {
    if (event.metaKey) {
      event.preventDefault();
      event.stopPropagation();
      if (currentWorkspaceId !== workspace.id) {
        goToWorkspace(workspace);
      }
    }
  });
  return null;
}

function WorkspaceOption({
  workspace,
  index,
  currentWorkspaceId,
  goToWorkspace,
}: {
  workspace: SlimWorkspace;
  index: number;
  currentWorkspaceId: string;
  goToWorkspace: (workspace: SlimWorkspace) => void;
}) {
  const shortcutNumber = index + 1;
  const hasShortcut = index < 9;

  return (
    <DropdownMenuItem
      className="gap-2 p-2 capitalize"
      key={workspace.id}
      onSelect={() => {
        if (workspace.id !== currentWorkspaceId) {
          goToWorkspace(workspace);
        }
      }}
    >
      {workspace.name}
      {hasShortcut && (
        <DropdownMenuShortcut>⌘{shortcutNumber}</DropdownMenuShortcut>
      )}
    </DropdownMenuItem>
  );
}

export function WorkspaceSwitcher({
  slimWorkspaces,
  currentWorkspaceId,
}: {
  slimWorkspaces: SlimWorkspaces;
  currentWorkspaceId: string;
}) {
  const { openDialog } = useCreateWorkspaceDialog();
  const router = useRouter();
  const currentWorkspace = slimWorkspaces.find(
    (workspace) => workspace.id === currentWorkspaceId
  );

  function goToWorkspace(workspace: SlimWorkspace) {
    toast.success(`Navigating to ${workspace.name} workspace.`, {
      duration: 1000,
      position: "top-center",
    });
    router.push(getWorkspaceSubPath(workspace, "/home"));
  }
  return (
    <Fragment>
      {slimWorkspaces.map((workspace, index) => (
        <WorkspaceToggler
          currentWorkspaceId={currentWorkspaceId}
          goToWorkspace={goToWorkspace}
          index={index}
          key={workspace.id}
          workspace={workspace}
        />
      ))}
      <SidebarMenu>
        <SidebarMenuItem>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <SidebarMenuButton
                className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                data-testid="workspace-switcher-trigger"
                size="lg"
              >
                <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-sidebar-primary text-sidebar-primary-foreground">
                  <Home className="size-4" />
                </div>
                <div className="grid flex-1 text-left text-sm leading-tight">
                  <span className="truncate font-semibold">
                    {currentWorkspace?.name ?? "Select Workspace"}
                  </span>
                  <span className="truncate text-xs">
                    {currentWorkspace?.membershipType === "solo"
                      ? "Personal"
                      : "Team"}{" "}
                    Workspace
                  </span>
                </div>
                <ChevronsUpDown className="ml-auto" />
              </SidebarMenuButton>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="start"
              className="w-(--radix-dropdown-menu-trigger-width) min-w-56 rounded-lg"
              side="bottom"
              sideOffset={4}
            >
              <DropdownMenuLabel className="text-muted-foreground text-xs">
                Workspaces
              </DropdownMenuLabel>
              <DropdownMenuSeparator />
              {slimWorkspaces.map((workspace, index) => (
                <WorkspaceOption
                  currentWorkspaceId={currentWorkspaceId}
                  goToWorkspace={goToWorkspace}
                  index={index}
                  key={workspace.id}
                  workspace={workspace}
                />
              ))}
              <DropdownMenuSeparator />
              <DropdownMenuItem className="gap-2 p-2" onSelect={openDialog}>
                <div
                  className="flex size-6 items-center justify-center rounded-md border bg-background"
                  data-testid="ws-create-workspace-trigger"
                >
                  <Plus className="size-4" />
                </div>
                <div className="font-medium text-muted-foreground">
                  Create Workspace
                </div>
                <DropdownMenuShortcut>w</DropdownMenuShortcut>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </SidebarMenuItem>
      </SidebarMenu>
    </Fragment>
  );
}
