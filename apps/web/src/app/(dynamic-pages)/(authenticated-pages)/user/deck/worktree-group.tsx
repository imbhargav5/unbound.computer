"use client";

import { ChevronRight, GitBranch } from "lucide-react";
import { useState } from "react";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import type { CardSize } from "@/hooks/use-deck-config";
import type { DeckSession } from "@/data/user/deck-sessions";
import { SessionCard } from "./session-card";

type WorktreeGroupProps = {
  label: string;
  isMain?: boolean;
  sessions: DeckSession[];
  cardSize: CardSize;
};

export function WorktreeGroup({
  label,
  isMain = false,
  sessions,
  cardSize,
}: WorktreeGroupProps) {
  const [isOpen, setIsOpen] = useState(true);

  if (sessions.length === 0) {
    return null;
  }

  return (
    <Collapsible onOpenChange={setIsOpen} open={isOpen}>
      <CollapsibleTrigger className="flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-muted-foreground text-xs transition-colors hover:bg-accent/50 hover:text-foreground">
        <ChevronRight
          className={`h-3 w-3 shrink-0 transition-transform ${isOpen ? "rotate-90" : ""}`}
        />
        <GitBranch className="h-3 w-3 shrink-0" />
        <span
          className={`truncate ${isMain ? "font-semibold" : "font-medium"}`}
        >
          {label}
        </span>
        <span className="ml-auto shrink-0 tabular-nums">{sessions.length}</span>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="mt-1 space-y-1.5 pl-1">
          {sessions.map((session) => (
            <SessionCard key={session.id} session={session} size={cardSize} />
          ))}
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}
