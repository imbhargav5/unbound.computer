"use client";

import type { getUserRepositories } from "@/data/user/repositories";
import type { DeckSession } from "@/data/user/deck-sessions";
import { DeckColumn } from "./deck-column";
import { WorktreeGroup } from "./worktree-group";

type Repository = Awaited<ReturnType<typeof getUserRepositories>>[number];

type HomeDeckProps = {
  repositories: Repository[];
  sessions: DeckSession[];
};

/**
 * Groups sessions by repository, then by worktree within each repo.
 * Main branch sessions come first, followed by worktree sessions.
 */
function groupSessionsByRepo(
  repositories: Repository[],
  sessions: DeckSession[],
) {
  const repoMap = new Map<
    string,
    {
      repo: Repository;
      mainSessions: DeckSession[];
      worktreeGroups: Map<string, DeckSession[]>;
    }
  >();

  for (const repo of repositories) {
    repoMap.set(repo.id, {
      repo,
      mainSessions: [],
      worktreeGroups: new Map(),
    });
  }

  for (const session of sessions) {
    if (!session.repository) {
      continue;
    }

    // Determine which parent repo this session belongs to
    const parentRepoId = session.repository.is_worktree
      ? session.repository.parent_repository_id
      : session.repository.id;

    if (!parentRepoId) {
      continue;
    }

    const group = repoMap.get(parentRepoId);
    if (!group) {
      continue;
    }

    if (session.repository.is_worktree) {
      const worktreeBranch =
        session.repository.worktree_branch ??
        session.current_branch ??
        "worktree";
      const existing = group.worktreeGroups.get(worktreeBranch);
      if (existing) {
        existing.push(session);
      } else {
        group.worktreeGroups.set(worktreeBranch, [session]);
      }
    } else {
      group.mainSessions.push(session);
    }
  }

  return repoMap;
}

export function HomeDeck({ repositories, sessions }: HomeDeckProps) {
  const grouped = groupSessionsByRepo(repositories, sessions);

  if (repositories.length === 0) {
    return (
      <div className="flex h-64 items-center justify-center text-muted-foreground">
        <div className="text-center">
          <p className="font-medium">No repositories yet</p>
          <p className="mt-1 text-sm">
            Start a Claude Code session from your terminal to see it here.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex gap-4 overflow-x-auto pb-4">
      {repositories.map((repo) => {
        const group = grouped.get(repo.id);
        if (!group) {
          return null;
        }

        const totalSessions =
          group.mainSessions.length +
          Array.from(group.worktreeGroups.values()).reduce(
            (sum, arr) => sum + arr.length,
            0,
          );

        return (
          <DeckColumn
            cardSize="small"
            key={repo.id}
            sessionCount={totalSessions}
            title={repo.name}
          >
            <WorktreeGroup
              cardSize="small"
              isMain
              label={repo.default_branch ?? "main"}
              sessions={group.mainSessions}
            />
            {Array.from(group.worktreeGroups.entries()).map(
              ([branch, worktreeSessions]) => (
                <WorktreeGroup
                  cardSize="small"
                  key={branch}
                  label={branch}
                  sessions={worktreeSessions}
                />
              ),
            )}
            {totalSessions === 0 && (
              <div className="px-2 py-4 text-center text-muted-foreground text-xs">
                No sessions
              </div>
            )}
          </DeckColumn>
        );
      })}
    </div>
  );
}
