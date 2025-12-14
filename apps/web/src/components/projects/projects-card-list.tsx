"use client";

import { format } from "date-fns";
import { CalendarDays, Clock, Link as LinkIcon } from "lucide-react";
import { motion } from "motion/react";
import { Link } from "@/components/intl-link";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { ScrollArea, ScrollBar } from "@/components/ui/scroll-area";
import type { DBTable } from "@/types";
import { cn } from "@/utils/cn";

export enum ProjectStatus {
  draft = "draft",
  pending_approval = "in review",
  approved = "in progress",
  completed = "completed",
}

const statusEmojis = {
  draft: "📝",
  pending_approval: "⏳",
  approved: "🏗️",
  completed: "✅",
};

const MotionCard = motion(Card);
const MotionCardContent = motion(CardContent);

const cardVariants = {
  hidden: { opacity: 0, y: 20 },
  visible: { opacity: 1, y: 0 },
};

const contentVariants = {
  hidden: { opacity: 0 },
  visible: { opacity: 1, transition: { staggerChildren: 0.1 } },
};

const itemVariants = {
  hidden: { opacity: 0, y: 10 },
  visible: { opacity: 1, y: 0 },
};

export const ProjectsCardList = ({
  projects,
}: {
  projects: DBTable<"projects">[];
}) => {
  if (projects.length === 0) {
    return (
      <p className="my-6 text-muted-foreground">
        🔍 No matching projects found.
      </p>
    );
  }

  return (
    <ScrollArea className="w-full">
      <div
        className={cn(
          "flex pb-4", // Common styles
          "flex-col space-y-4", // Mobile styles
          "sm:flex-row sm:space-x-4 sm:space-y-0" // sm and above styles
        )}
      >
        {projects.slice(0, 5).map((project, index) => (
          <MotionCard
            animate="visible"
            className={cn(
              "shadow-xs", // Common styles
              "w-full", // Mobile styles
              "sm:w-[300px]" // sm and above styles
            )}
            initial="hidden"
            key={project.id}
            transition={{ duration: 0.3, delay: index * 0.1 }}
            variants={cardVariants}
          >
            <Link className="block p-4" href={`/project/${project.slug}`}>
              <MotionCardContent
                animate="visible"
                className="space-y-3 p-0"
                initial="hidden"
                variants={contentVariants}
              >
                <motion.div
                  className="flex items-center justify-between"
                  variants={itemVariants}
                >
                  <Badge className="font-normal text-xs" variant="secondary">
                    {statusEmojis[project.project_status]}{" "}
                    {capitalizeFirstLetter(project.project_status)}
                  </Badge>
                  <span className="text-muted-foreground text-xs">
                    ID: {project.id.slice(0, 7)}
                  </span>
                </motion.div>
                <motion.h2
                  className="font-semibold text-lg"
                  variants={itemVariants}
                >
                  {project.name}
                </motion.h2>
                <motion.div
                  className="flex items-center text-muted-foreground text-xs"
                  variants={itemVariants}
                >
                  <CalendarDays className="mr-1 h-3 w-3" />
                  <span>
                    Created:{" "}
                    {format(new Date(project.created_at), "dd MMM yyyy")}
                  </span>
                </motion.div>
                <motion.div
                  className="flex items-center text-muted-foreground text-xs"
                  variants={itemVariants}
                >
                  <Clock className="mr-1 h-3 w-3" />
                  <span>
                    Updated:{" "}
                    {format(new Date(project.updated_at), "dd MMM yyyy")}
                  </span>
                </motion.div>
                <motion.div
                  className="flex items-center text-muted-foreground text-xs"
                  variants={itemVariants}
                >
                  <LinkIcon className="mr-1 h-3 w-3" />
                  <span className="truncate">/{project.slug}</span>
                </motion.div>
              </MotionCardContent>
            </Link>
          </MotionCard>
        ))}
      </div>
      <ScrollBar orientation="horizontal" />
    </ScrollArea>
  );
};

function capitalizeFirstLetter(string: string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
}
