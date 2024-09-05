'use client';

import { ProFeatureGateDialog } from '@/components/ProFeatureGateDialog';
import { SwitcherAndToggle } from '@/components/SidebarComponents/SidebarLogo';
import { SidebarLink } from '@/components/SidebarLink';
import { SlimWorkspace, SlimWorkspaces } from '@/types';
import { cn } from '@/utils/cn';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { motion } from 'framer-motion';
import { DollarSign, FileBox, Home, Layers, Settings, UserRound } from 'lucide-react';
import { ReactNode } from 'react';

const sidebarLinks = [
  { label: "Home", href: "", icon: <Home className="h-5 w-5" /> },
  { label: "Settings", href: "/settings", icon: <Settings className="h-5 w-5" /> },
  { label: "Projects", href: "/projects", icon: <Layers className="h-5 w-5" /> },
  { label: "Members", href: "/settings/members", icon: <UserRound className="h-5 w-5" /> },
  { label: "Billing", href: "/settings/billing", icon: <DollarSign className="h-5 w-5" /> },
];

const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.1,
      delayChildren: 0.2,
    },
  },
};

const itemVariants = {
  hidden: { opacity: 0, x: -20 },
  visible: {
    opacity: 1,
    x: 0,
    transition: {
      type: 'spring',
      stiffness: 300,
      damping: 24,
    }
  },
};

interface WorkspaceSidebarClientProps {
  workspaceId: string;
  workspaceSlug: string;
  slimWorkspaces: SlimWorkspaces;
  subscription: ReactNode
  workspace: SlimWorkspace
}

export default function WorkspaceSidebarClient({
  workspaceId,
  workspaceSlug,
  slimWorkspaces,
  subscription,
  workspace
}: WorkspaceSidebarClientProps) {
  return (
    <motion.div
      className={cn(
        'flex flex-col justify-between h-full',
        'lg:px-3 lg:py-4 lg:pt-2.5 ',
      )}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.5 }}
    >
      <div>
        <div className="flex justify-between items-center">
          <SwitcherAndToggle workspaceId={workspaceId} slimWorkspaces={slimWorkspaces} />
        </div>
        <motion.nav
          className="flex flex-col gap-2 mt-6"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          {sidebarLinks.map((link) => (
            <motion.div key={link.label} variants={itemVariants}>
              <SidebarLink
                label={link.label}
                href={getWorkspaceSubPath(workspace, link.href)}
                icon={link.icon}
              />
            </motion.div>
          ))}
          <motion.div variants={itemVariants}>
            <ProFeatureGateDialog
              workspace={workspace}
              label="Feature Pro"
              icon={<FileBox className="h-5 w-5" />}
            />
          </motion.div>
        </motion.nav>
      </div>
      <motion.div
        className="mt-auto"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5, duration: 0.3 }}
      >
        {subscription}
      </motion.div>
    </motion.div>
  );
}
