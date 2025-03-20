"use client";

import { motion } from "motion/react";

export function DashboardClientWrapper({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.5 }}
      className="space-y-8 py-8 container"
    >
      {children}
    </motion.div>
  );
}
