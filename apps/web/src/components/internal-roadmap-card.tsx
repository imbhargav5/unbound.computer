import { Bug, Calendar, Command, EyeIcon, Info, Pencil } from "lucide-react";
import type { ComponentProps, HtmlHTMLAttributes } from "react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import type { Enum } from "@/types";
import { formatFieldValue } from "@/utils/feedback";
import { Badge } from "./ui/badge";

type BadgeProps = ComponentProps<typeof Badge>;

type InternalRoadmapCardProps = {
  title: string;
  description: string;
  tag: Enum<"marketing_feedback_thread_type">;
  date: string;
  priority: Enum<"marketing_feedback_thread_priority">;
  feedbackItemId: string;
  isAdmin?: boolean;
};

const getIconVariantForTag = (tag: Enum<"marketing_feedback_thread_type">) => {
  switch (tag) {
    case "bug":
      return <Bug className="mr-2 h-4 w-4" />;
    case "general":
      return <Info className="mr-2 h-4 w-4" />;
    case "feature_request":
      return <Command className="mr-2 h-4 w-4" />;
    default:
      return null;
  }
};

const getPriorityVariant = (
  priority: Enum<"marketing_feedback_thread_priority">
): BadgeProps["variant"] => {
  switch (priority) {
    case "high":
      return "destructive";
    case "medium":
      return "default";
    case "low":
      return "outline";
    default:
      return "default";
  }
};

export default function InternalRoadmapCard({
  title,
  description,
  tag,
  date,
  priority,
  feedbackItemId,
  isAdmin,
  ...rest
}: InternalRoadmapCardProps & HtmlHTMLAttributes<HTMLDivElement>) {
  return (
    <div
      {...rest}
      className="grid grid-cols-[1fr_auto] items-start gap-1 rounded-xl border bg-white p-4 dark:bg-slate-900"
    >
      <div className="space-y-4">
        <div className="space-y-1">
          <p className="font-semibold text-lg">{title}</p>
          <p className="text-base text-muted-foreground">{description}</p>
        </div>

        <div className="-mb-0.5 mt-3">
          <div className="mb-3 flex space-x-2">
            <Badge variant="outline">
              {getIconVariantForTag(tag)}
              {formatFieldValue(tag)}
            </Badge>
            <Badge variant={"outline"}>{formatFieldValue(priority)}</Badge>
          </div>

          <div className="flex items-center text-muted-foreground text-sm">
            <Calendar className="mr-2 h-4 w-4" />
            <span className="font-semibold">{date}</span>
          </div>
        </div>
      </div>

      <Link className="mt-1" href={`/feedback/${feedbackItemId}`}>
        <Button size="icon" variant={"ghost"}>
          {isAdmin ? (
            <Pencil className="h-4 w-4" />
          ) : (
            <EyeIcon className="h-4 w-4" />
          )}
        </Button>
      </Link>
    </div>
  );
}
