'use client';

import { CreateOrganizationDialog } from '@/components/CreateOrganizationDialog';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { motion } from 'framer-motion';
import { Check, ChevronsUpDown, UsersRound } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

export function OrganizationSwitcher({
  slimOrganizations,
  currentOrganizationId,
}: {
  slimOrganizations: Array<{
    id: string;
    title: string;
    slug: string;
  }>;
  currentOrganizationId: string;
}) {
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const router = useRouter();
  const currentOrganization = slimOrganizations.find(
    (organization) => organization.id === currentOrganizationId,
  );

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
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
              {currentOrganization?.title ?? 'Select Organization'}
            </span>
            <ChevronsUpDown className="h-4 w-4 shrink-0 opacity-0 group-hover:opacity-50 ml-2 transition-opacity" />
          </motion.div>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-[240px]">
        <DropdownMenuLabel>Organizations</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {slimOrganizations.map((organization) => (
          <DropdownMenuItem
            key={organization.id}
            onSelect={() => {
              router.push(`/${organization.slug}`);
            }}
          >
            <motion.div
              className="flex items-center justify-between w-full"
              initial={{ opacity: 0, y: -5 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.15 }}
            >
              {organization.title}
              {organization.id === currentOrganizationId && (
                <Check className="h-4 w-4 text-primary" />
              )}
            </motion.div>
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={() => setIsDialogOpen(true)}>
          <motion.div
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className="w-full"
          >
            Create Organization
          </motion.div>
        </DropdownMenuItem>
      </DropdownMenuContent>
      <CreateOrganizationDialog
        isDialogOpen={isDialogOpen}
        setIsDialogOpen={setIsDialogOpen}
      />
    </DropdownMenu>
  );
}
