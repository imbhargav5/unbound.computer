"use client";

import { Bell } from "lucide-react";
import { motion } from "motion/react";
import { Card } from "@/components/ui/card";
import { T } from "@/components/ui/typography-ui";

export function EmptyState() {
  return (
    <motion.div
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0 }}
      initial={{ opacity: 0, y: 20 }}
      transition={{ duration: 0.3 }}
    >
      <Card className="mt-8 flex flex-col items-center justify-center border-dashed p-12">
        <div className="mb-6 flex h-24 w-24 animate-pulse items-center justify-center rounded-full bg-primary/10">
          <Bell className="h-12 w-12 text-primary" />
        </div>
        <T.H3 className="mb-3 text-center font-semibold">
          Your notifications will appear here
        </T.H3>
        <T.P className="max-w-md text-center text-muted-foreground">
          When you receive notifications about your activities, mentions, or
          updates, they will show up here. Check back later for new
          notifications.
        </T.P>
      </Card>
    </motion.div>
  );
}
