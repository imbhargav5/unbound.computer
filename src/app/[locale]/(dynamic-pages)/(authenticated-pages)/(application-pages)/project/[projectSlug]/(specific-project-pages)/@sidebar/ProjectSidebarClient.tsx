'use client';

import { SwitcherAndToggle } from '@/components/SidebarComponents/SidebarLogo';
import { SidebarLink } from '@/components/SidebarLink';
import { cn } from '@/utils/cn';
import { motion } from 'framer-motion';
import { ArrowLeft, Bird, History, Image, Layers, Settings } from 'lucide-react';

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
  projectId: string;
  projectSlug: string;
  organizationId: string;
  organizationSlug: string;
  project: any; // Replace with the correct type
  slimOrganizations: any[]; // Replace with the correct type
}

export function ProjectSidebarClient({
  projectId,
  projectSlug,
  organizationId,
  organizationSlug,
  project,
  slimOrganizations
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
        <SwitcherAndToggle organizationId={organizationId} slimOrganizations={slimOrganizations} />
        <motion.div
          className="flex flex-col"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Back to organization"
              href={`/${organizationSlug}`}
              icon={<ArrowLeft className="h-5 w-5" />}
            />
          </motion.div>

          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Project Home"
              href={`/project/${projectSlug}`}
              icon={<Layers className="h-5 w-5" />}
            />
          </motion.div>
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Image Generator"
              href={`/project/${projectSlug}/image-generator`}
              icon={<Image className="h-5 w-5" />}
            />
          </motion.div>
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Post Generator"
              href={`/project/${projectSlug}/post-generator`}
              icon={<Bird className="h-5 w-5" />}
            />
          </motion.div>
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Project Settings"
              href={`/project/${projectSlug}/settings`}
              icon={<Settings className="h-5 w-5" />}
            />
          </motion.div>
          <motion.div variants={itemVariants}>
            <SidebarLink
              label="Chats"
              href={`/project/${projectSlug}/chats`}
              icon={<History className="h-5 w-5" />}
            />
          </motion.div>
        </motion.div>
      </div>

    </motion.div>
  );
}
