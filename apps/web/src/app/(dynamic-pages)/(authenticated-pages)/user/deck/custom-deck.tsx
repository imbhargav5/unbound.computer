"use client";

import type { DeckConfig, StatusFilter } from "@/hooks/use-deck-config";
import type { DeckSession } from "@/data/user/deck-sessions";
import type { getUserRepositories } from "@/data/user/repositories";
import { DeckColumn } from "./deck-column";
import { DeckToolbar } from "./deck-toolbar";
import { SessionCard } from "./session-card";

type Repository = Awaited<ReturnType<typeof getUserRepositories>>[number];

type CustomDeckProps = {
  deck: DeckConfig;
  sessions: DeckSession[];
  repositories: Repository[];
  onAddColumn: () => void;
  onRemoveColumn: (columnId: string) => void;
  onDeleteDeck: () => void;
  onRenameDeck: (name: string) => void;
};

function filterSessions(
  sessions: DeckSession[],
  repositoryId: string,
  statusFilter: StatusFilter,
): DeckSession[] {
  return sessions.filter((s) => {
    if (!s.repository) {
      return false;
    }

    // Match sessions for this repo or its worktrees
    const matchesRepo =
      s.repository.id === repositoryId ||
      s.repository.parent_repository_id === repositoryId;

    if (!matchesRepo) {
      return false;
    }

    if (statusFilter === "all") {
      return true;
    }

    return s.status === statusFilter;
  });
}

export function CustomDeck({
  deck,
  sessions,
  repositories,
  onAddColumn,
  onRemoveColumn,
  onDeleteDeck,
  onRenameDeck,
}: CustomDeckProps) {
  return (
    <div className="flex flex-col gap-4">
      <DeckToolbar
        deckName={deck.name}
        onAddColumn={onAddColumn}
        onDeleteDeck={onDeleteDeck}
        onRenameDeck={onRenameDeck}
      />
      {deck.columns.length === 0 ? (
        <div className="flex h-64 items-center justify-center text-muted-foreground">
          <div className="text-center">
            <p className="font-medium">No columns yet</p>
            <p className="mt-1 text-sm">
              Add a column to start customizing this deck.
            </p>
          </div>
        </div>
      ) : (
        <div className="flex gap-4 overflow-x-auto pb-4">
          {deck.columns.map((column) => {
            const filteredSessions = filterSessions(
              sessions,
              column.repositoryId,
              column.statusFilter,
            );

            return (
              <DeckColumn
                cardSize={column.cardSize}
                key={column.id}
                onRemove={() => onRemoveColumn(column.id)}
                sessionCount={filteredSessions.length}
                title={column.repositoryName}
              >
                {filteredSessions.length === 0 ? (
                  <div className="px-2 py-4 text-center text-muted-foreground text-xs">
                    No matching sessions
                  </div>
                ) : (
                  filteredSessions.map((session) => (
                    <SessionCard
                      key={session.id}
                      session={session}
                      size={column.cardSize}
                    />
                  ))
                )}
              </DeckColumn>
            );
          })}
        </div>
      )}
    </div>
  );
}
