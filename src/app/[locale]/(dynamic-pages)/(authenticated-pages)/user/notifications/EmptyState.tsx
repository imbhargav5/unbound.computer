"use client";

import { Card } from "@/components/ui/card";
import { T } from "@/components/ui/Typography";
import { Bell } from "lucide-react";
import { motion } from "motion/react";

export function EmptyState() {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.3 }}
    >
      <Card className="flex flex-col items-center justify-center p-12 mt-8 border-dashed">
        <div className="h-24 w-24 rounded-full bg-primary/10 flex items-center justify-center mb-6 animate-pulse">
          <Bell className="h-12 w-12 text-primary" />
        </div>
        <T.H3 className="font-semibold text-center mb-3">
          Your notifications will appear here
        </T.H3>
        <T.P className="text-muted-foreground text-center max-w-md">
          When you receive notifications about your activities, mentions, or
          updates, they will show up here. Check back later for new
          notifications.
        </T.P>
      </Card>
    </motion.div>
  );
}
