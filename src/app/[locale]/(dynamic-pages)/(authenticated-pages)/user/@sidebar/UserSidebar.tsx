"use client";

import { SwitcherAndToggle } from "@/components/SidebarComponents/SwitcherAndToggle";
import { SidebarLink } from "@/components/SidebarLink";
import { cn } from "@/utils/cn";
import { motion } from "framer-motion";
import { Code, FileQuestion, Home, Mail, Settings, Shield } from "lucide-react";

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
      type: "spring",
      stiffness: 300,
      damping: 24,
    },
  },
};

const sidebarLinks = [
  {
    label: "Dashboard",
    href: "/dashboard",
    icon: <Home className="h-5 w-5" />,
  },
  {
    label: "Account Settings",
    href: "/user/settings",
    icon: <Settings className="h-5 w-5" />,
  },
  {
    label: "Security Settings",
    href: "/user/settings/security",
    icon: <Shield className="h-5 w-5" />,
  },
  {
    label: "Developer Settings",
    href: "/user/settings/developer",
    icon: <Code className="h-5 w-5" />,
  },
  {
    label: "Invitations",
    href: "/user/invitations",
    icon: <Mail className="h-5 w-5" />,
  },
  {
    label: "My Feedback",
    href: "/feedback",
    icon: <FileQuestion className="h-5 w-5" />,
  },
];

export function UserSidebar() {
  return (
    <motion.div
      className={cn(
        "flex flex-col justify-between h-full",
        "lg:px-3 lg:py-4 lg:pt-2.5",
      )}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.5 }}
    >
      <div>
        <motion.div
          className="flex justify-between items-center"
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.3 }}
        >
          <SwitcherAndToggle />
        </motion.div>
        <motion.div
          className="mt-6"
          variants={containerVariants}
          initial="hidden"
          animate="visible"
        >
          {sidebarLinks.map((link) => (
            <motion.div key={link.href} variants={itemVariants}>
              <SidebarLink
                label={link.label}
                href={link.href}
                icon={link.icon}
              />
            </motion.div>
          ))}
        </motion.div>
      </div>
    </motion.div>
  );
}
