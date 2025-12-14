"use server";
import {
  Bug,
  LucideCloudLightning,
  MessageSquare,
  ThumbsUp,
} from "lucide-react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { T } from "@/components/ui/typography-ui";
import { NEW_STATUS_OPTIONS } from "@/utils/feedback";
import { FeedbackAvatarServer } from "../../feedback/[feedbackId]/feedback-avatar-server";
import type { RoadmapItem } from "../types";

const typeIcons = {
  bug: <Bug className="mr-1 h-3 w-3 text-destructive" />,
  feature_request: (
    <LucideCloudLightning className="mr-1 h-3 w-3 text-primary" />
  ),
  general: <MessageSquare className="mr-1 h-3 w-3 text-secondary" />,
};

const TAGS = {
  bug: "Bug",
  feature_request: "Feature Request",
  general: "General",
};

const PRIORITY_BADGES = {
  low: { label: "Low Priority", className: "bg-muted text-muted-foreground" },
  medium: {
    label: "Medium Priority",
    className: "bg-blue-500/10 text-blue-500",
  },
  high: {
    label: "High Priority",
    className: "bg-orange-500/10 text-orange-500",
  },
  urgent: { label: "Urgent", className: "bg-destructive/10 text-destructive" },
} as const;

interface RoadmapListProps {
  cards: RoadmapItem[];
  isAdmin?: boolean;
}

export async function RoadmapList({ cards, isAdmin }: RoadmapListProps) {
  return (
    <div className="flex-1 divide-y divide-border overflow-auto">
      {cards.map((item) => {
        const statusOption = NEW_STATUS_OPTIONS.find(
          (option) => option.value === item.status
        );

        return (
          <Link href={`/feedback/${item.id}`} key={item.id}>
            <div
              className="rounded px-4 py-3 transition-colors duration-200"
              key={item.id}
            >
              <div className="space-y-2">
                <T.H4 className="mt-0 line-clamp-1 pt-0 font-semibold text-base">
                  {item.title}
                </T.H4>

                <T.Small className="line-clamp-2 block text-muted-foreground">
                  {item.content}
                </T.Small>

                <div className="flex items-center justify-between pt-2">
                  <FeedbackAvatarServer feedback={item} />

                  <div className="flex items-center gap-2">
                    <div className="flex items-center gap-1.5">
                      {statusOption && (
                        <Badge
                          className="flex h-5 items-center gap-1 rounded-full px-1.5 py-0 text-[0.7rem]"
                          variant="secondary"
                        >
                          <statusOption.icon className="h-2.5 w-2.5" />
                          {statusOption.label}
                        </Badge>
                      )}
                      <Badge
                        className="flex h-5 items-center gap-1 rounded-full px-1.5 py-0 text-[0.7rem]"
                        variant="secondary"
                      >
                        {typeIcons[item.type]} {TAGS[item.type]}
                      </Badge>
                    </div>

                    <div className="flex items-center gap-2 border-l pl-2">
                      <div className="flex items-center gap-1">
                        <MessageSquare className="h-3.5 w-3.5 text-muted-foreground" />
                        <span className="text-muted-foreground text-xs">
                          {item.comment_count}
                        </span>
                      </div>
                      <div className="flex items-center gap-1">
                        <ThumbsUp className="h-3.5 w-3.5 text-muted-foreground" />
                        <span className="text-muted-foreground text-xs">
                          {item.reaction_count}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </Link>
        );
      })}
    </div>
  );
}
