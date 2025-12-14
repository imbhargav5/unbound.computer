import {
  ArrowDownIcon,
  ArrowRightIcon,
  ArrowUpIcon,
  CalendarIcon,
  CheckCircledIcon,
  LightningBoltIcon,
  QuestionMarkCircledIcon,
  ReaderIcon,
  StopwatchIcon,
} from "@radix-ui/react-icons";
import { Bug, MessageSquareDotIcon, XCircle } from "lucide-react";
import type { ComponentProps } from "react";
import type { Badge } from "@/components/ui/badge";
import type { Enum } from "@/types";

type BadgeProps = ComponentProps<typeof Badge>;

// Semantic color configs for badges
export const statusConfig: Record<
  Enum<"marketing_feedback_thread_status">,
  { label: string; className: string }
> = {
  open: {
    label: "Open",
    className:
      "bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950 dark:text-amber-400 dark:border-amber-800",
  },
  under_review: {
    label: "Under Review",
    className:
      "bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-950 dark:text-blue-400 dark:border-blue-800",
  },
  planned: {
    label: "Planned",
    className:
      "bg-violet-50 text-violet-700 border-violet-200 dark:bg-violet-950 dark:text-violet-400 dark:border-violet-800",
  },
  in_progress: {
    label: "In Progress",
    className:
      "bg-sky-50 text-sky-700 border-sky-200 dark:bg-sky-950 dark:text-sky-400 dark:border-sky-800",
  },
  completed: {
    label: "Completed",
    className:
      "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-950 dark:text-emerald-400 dark:border-emerald-800",
  },
  closed: {
    label: "Closed",
    className:
      "bg-gray-50 text-gray-700 border-gray-200 dark:bg-gray-950 dark:text-gray-400 dark:border-gray-800",
  },
  moderator_hold: {
    label: "On Hold",
    className:
      "bg-orange-50 text-orange-700 border-orange-200 dark:bg-orange-950 dark:text-orange-400 dark:border-orange-800",
  },
};

export const typeConfig: Record<
  Enum<"marketing_feedback_thread_type">,
  { label: string; className: string }
> = {
  bug: {
    label: "Bug",
    className:
      "bg-red-50 text-red-700 border-red-200 dark:bg-red-950 dark:text-red-400 dark:border-red-800",
  },
  feature_request: {
    label: "Feature Request",
    className: "bg-secondary text-secondary-foreground",
  },
  general: {
    label: "General",
    className: "bg-secondary text-secondary-foreground",
  },
};

export const formatFieldValue = (type: string) => {
  // feature_request to Feature request
  return type.replace(/_/g, " ").replace(/\b\w/g, (l) => l.toUpperCase());
};

export const STATUS_OPTIONS: Array<Enum<"marketing_feedback_thread_status">> = [
  "open",
  "in_progress",
  "closed",
  "planned",
  "under_review",
];

export const NEW_STATUS_OPTIONS: Array<{
  value: Enum<"marketing_feedback_thread_status">;
  label: string;
  icon: React.ElementType;
}> = [
  {
    label: "Open",
    value: "open",
    icon: QuestionMarkCircledIcon,
  },
  {
    label: "In Progress",
    value: "in_progress",
    icon: StopwatchIcon,
  },
  {
    label: "Closed",
    value: "closed",
    icon: XCircle,
  },
  {
    label: "Planned",
    value: "planned",
    icon: CalendarIcon,
  },
  {
    label: "Under Review",
    value: "under_review",
    icon: ReaderIcon,
  },
  {
    label: "Completed",
    value: "completed",
    icon: CheckCircledIcon,
  },
];

export const NEW_PRIORITY_OPTIONS: Array<{
  value: Enum<"marketing_feedback_thread_priority">;
  label: string;
  icon: React.ElementType;
}> = [
  {
    label: "Low",
    value: "low",
    icon: ArrowDownIcon,
  },
  {
    label: "Medium",
    value: "medium",
    icon: ArrowRightIcon,
  },
  {
    label: "High",
    value: "high",
    icon: ArrowUpIcon,
  },
];

export const NEW_TYPE_OPTIONS: Array<{
  value: Enum<"marketing_feedback_thread_type">;
  label: string;
  icon: React.ElementType;
}> = [
  {
    label: "Bug",
    value: "bug",
    icon: Bug,
  },
  {
    label: "Feature Request",
    value: "feature_request",
    icon: LightningBoltIcon,
  },
  {
    label: "General",
    value: "general",
    icon: MessageSquareDotIcon,
  },
];

export const PRIORITY_OPTIONS: Array<
  Enum<"marketing_feedback_thread_priority">
> = ["low", "medium", "high"];

export const TYPE_OPTIONS: Array<Enum<"marketing_feedback_thread_type">> = [
  "bug",
  "feature_request",
  "general",
];

export const mapStatusToVariant = (
  status: Enum<"marketing_feedback_thread_status">
): BadgeProps["variant"] => {
  switch (status) {
    case "closed":
      return "outline";
    case "open":
    case "in_progress":
      return "default";
    case "planned":
    case "under_review":
      return "secondary";
    default:
      return "default";
  }
};

export const mapTypeToVariant = (
  type: Enum<"marketing_feedback_thread_type">
): BadgeProps["variant"] => {
  switch (type) {
    case "bug":
      return "destructive";
    case "feature_request":
      return "secondary";
    case "general":
      return "default";
    default:
      return "default";
  }
};

export const mapPriorityToVariant = (
  priority: Enum<"marketing_feedback_thread_priority">
): BadgeProps["variant"] => {
  switch (priority) {
    case "low":
      return "outline";
    case "medium":
      return "default";
    case "high":
      return "destructive";
    default:
      return "default";
  }
};
