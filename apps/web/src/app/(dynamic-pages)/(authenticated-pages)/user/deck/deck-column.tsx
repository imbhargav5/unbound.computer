"use client";

import { FolderGit2, X } from "lucide-react";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import type { CardSize } from "@/hooks/use-deck-config";

type DeckColumnProps = {
  title: string;
  sessionCount: number;
  cardSize: CardSize;
  children: React.ReactNode;
  onRemove?: () => void;
};

const columnWidthMap: Record<CardSize, string> = {
  small: "w-72",
  medium: "w-80",
  large: "w-96",
};

export function DeckColumn({
  title,
  sessionCount,
  cardSize,
  children,
  onRemove,
}: DeckColumnProps) {
  return (
    <div
      className={`${columnWidthMap[cardSize]} flex shrink-0 flex-col rounded-lg border bg-muted/30`}
      style={{ maxHeight: "calc(100vh - 140px)" }}
    >
      <div className="flex items-center gap-2 border-b px-3 py-2.5">
        <FolderGit2 className="h-4 w-4 shrink-0 text-muted-foreground" />
        <span className="min-w-0 flex-1 truncate font-semibold text-sm">
          {title}
        </span>
        <Badge className="shrink-0" variant="secondary">
          {sessionCount}
        </Badge>
        {onRemove && (
          <Button
            className="h-6 w-6 shrink-0"
            onClick={onRemove}
            size="icon"
            variant="ghost"
          >
            <X className="h-3 w-3" />
          </Button>
        )}
      </div>
      <ScrollArea className="flex-1 px-2 py-2">
        <div className="space-y-2">{children}</div>
      </ScrollArea>
    </div>
  );
}
