"use client";

import { motion } from "motion/react";

export function DashboardClientWrapper({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <motion.div
      animate={{ opacity: 1 }}
      className="container space-y-8"
      initial={{ opacity: 0 }}
      transition={{ duration: 0.5 }}
    >
      {children}
    </motion.div>
  );
}
