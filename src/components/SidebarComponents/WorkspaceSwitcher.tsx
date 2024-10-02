'use client';

import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { useCreateWorkspaceDialog } from '@/contexts/CreateWorkspaceDialogContext';
import { SlimWorkspaces } from '@/types';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { motion } from 'framer-motion';
import { Check, ChevronsUpDown, UsersRound } from 'lucide-react';
import { useRouter } from 'next/navigation';

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
    (workspace) => workspace.id === currentWorkspaceId,
  );

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          data-testid="ws-select-trigger"
          variant="ghost"
          className="w-full justify-between px-3 py-2 text-left font-normal group max-w-[220px]"
        >
          <motion.div
            className="flex items-center gap-2 w-full"
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
          >
            <UsersRound className="h-4 w-4 shrink-0" />
            <span className="text-sm text-muted-foreground truncate flex-grow">
              {currentWorkspace?.name ?? 'Select Workspace'}
            </span>
            <ChevronsUpDown className="h-4 w-4 shrink-0 opacity-0 group-hover:opacity-50 ml-2 transition-opacity" />
          </motion.div>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-[240px]">
        <DropdownMenuLabel>Workspaces</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {slimWorkspaces.map((workspace) => (
          <DropdownMenuItem
            key={workspace.id}
            onSelect={() => {
              router.push(getWorkspaceSubPath(workspace, '/home'));
            }}
          >
            <motion.div
              className="flex items-center justify-between w-full"
              initial={{ opacity: 0, y: -5 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.15 }}
            >
              {workspace.name}
              {workspace.id === currentWorkspaceId && (
                <Check className="h-4 w-4 text-primary" />
              )}
            </motion.div>
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={openDialog}>
          <motion.div
            data-testid="ws-create-workspace-trigger"
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className="w-full"
          >
            Create Workspace
          </motion.div>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
