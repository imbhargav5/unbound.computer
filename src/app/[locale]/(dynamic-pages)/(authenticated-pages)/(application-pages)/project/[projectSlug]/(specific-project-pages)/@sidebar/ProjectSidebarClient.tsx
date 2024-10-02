'use client';

import { SwitcherAndToggle } from '@/components/SidebarComponents/SwitcherAndToggle';
import { SidebarLink } from '@/components/SidebarLink';
import { DBTable, SlimWorkspaces, WorkspaceWithMembershipType } from '@/types';
import { cn } from '@/utils/cn';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { motion } from 'framer-motion';
import { ArrowLeft, Bird, History, Layers, Settings } from 'lucide-react';

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

interface ProjectSidebarClientProps {

  workspace: WorkspaceWithMembershipType; // Replace with the correct type
  project: DBTable<'projects'>; // Replace with the correct type
  slimWorkspaces: SlimWorkspaces; // Replace with the correct type
}

export function ProjectSidebarClient({
  project,
  workspace,
  slimWorkspaces
}: ProjectSidebarClientProps) {
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
        <SwitcherAndToggle workspaceId={workspace.id} slimWorkspaces={slimWorkspaces} />
        <motion.div
          className="flex flex-col"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Back to workspace"
              href={getWorkspaceSubPath(workspace, `/home`)}
              icon={<ArrowLeft className="h-5 w-5" />}
            />
          </motion.div>

          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Project Home"
              href={`/project/${project.slug}`}
              icon={<Layers className="h-5 w-5" />}
            />
          </motion.div>
          {/* <motion.div variants={itemVariants}>
            <SidebarLink
              label="Image Generator"
              href={`/project/${project.slug}/image-generator`}
              icon={<Image className="h-5 w-5" />}
            />
          </motion.div> */}
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Post Generator"
              href={`/project/${project.slug}/post-generator`}
              icon={<Bird className="h-5 w-5" />}
            />
          </motion.div>
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Project Settings"
              href={`/project/${project.slug}/settings`}
              icon={<Settings className="h-5 w-5" />}
            />
          </motion.div>
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Chats"
              href={`/project/${project.slug}/chats`}
              icon={<History className="h-5 w-5" />}
            />
          </motion.div>
        </motion.div>
      </div>

    </motion.div>
  );
}
