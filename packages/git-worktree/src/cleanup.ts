import { isAncestor } from "./git.js";
import type {
  CleanupOptions,
  SessionWorktree,
  WorktreeConfig,
  WorktreeResult,
} from "./types.js";
import {
  listSessionWorktrees,
  pruneWorktrees,
  removeWorktree,
} from "./worktree.js";

/**
 * Result of cleanup operation
 */
export interface CleanupResult {
  /** Successfully cleaned worktrees */
  cleaned: SessionWorktree[];
  /** Worktrees that failed to clean */
  failed: Array<{ worktree: SessionWorktree; error: string }>;
  /** Worktrees that were skipped */
  skipped: Array<{ worktree: SessionWorktree; reason: string }>;
}

/**
 * Check if a worktree has been merged into the default branch
 */
async function isMerged(
  repoPath: string,
  worktree: SessionWorktree,
  targetBranch: string
): Promise<boolean> {
  if (!worktree.branch) {
    return false;
  }

  try {
    return await isAncestor(repoPath, worktree.head, targetBranch);
  } catch {
    return false;
  }
}

/**
 * Check if a worktree is stale (no activity within TTL)
 */
async function isStale(
  worktree: SessionWorktree,
  ttlMs: number
): Promise<boolean> {
  const now = Date.now();
  const lastActivity = worktree.lastActivityAt.getTime();
  return now - lastActivity > ttlMs;
}

/**
 * Cleanup worktrees using the specified strategy
 */
export async function cleanupWorktrees(
  repoPath: string,
  config: WorktreeConfig,
  options: CleanupOptions
): Promise<WorktreeResult<CleanupResult>> {
  const {
    strategy,
    ttlMs = config.defaultTtlMs,
    dryRun = false,
    force = false,
  } = options;

  const result: CleanupResult = {
    cleaned: [],
    failed: [],
    skipped: [],
  };

  try {
    // First, prune any invalid worktree references
    await pruneWorktrees(repoPath, dryRun);

    // Get all session worktrees
    const worktrees = await listSessionWorktrees(repoPath, config);

    for (const worktree of worktrees) {
      // Skip locked worktrees unless force is true
      if (worktree.isLocked && !force) {
        result.skipped.push({
          worktree,
          reason: `Worktree is locked: ${worktree.lockReason || "no reason given"}`,
        });
        continue;
      }

      // Determine if worktree should be cleaned based on strategy
      let shouldClean = false;
      let skipReason = "";

      switch (strategy) {
        case "manual":
          // Manual cleanup - clean everything that's passed in
          shouldClean = true;
          break;

        case "post-merge": {
          // Clean worktrees whose branches have been merged
          const merged = await isMerged(
            repoPath,
            worktree,
            worktree.baseBranch || "main"
          );
          if (merged) {
            shouldClean = true;
          } else {
            skipReason = "Branch not yet merged";
          }
          break;
        }

        case "timeout": {
          // Clean stale worktrees
          const stale = await isStale(worktree, ttlMs);
          if (stale) {
            shouldClean = true;
          } else {
            const remaining =
              ttlMs - (Date.now() - worktree.lastActivityAt.getTime());
            const hours = Math.round(remaining / (60 * 60 * 1000));
            skipReason = `Not stale yet (${hours}h remaining)`;
          }
          break;
        }

        case "on-demand":
          // Clean specific worktrees (usually specified by session ID)
          shouldClean = true;
          break;

        default:
          skipReason = `Unknown strategy: ${strategy}`;
      }

      if (!shouldClean) {
        result.skipped.push({ worktree, reason: skipReason });
        continue;
      }

      // Perform cleanup
      if (dryRun) {
        result.cleaned.push(worktree);
      } else {
        const removeResult = await removeWorktree(repoPath, worktree.path, {
          force,
          deleteBranch: true,
        });

        if (removeResult.success) {
          result.cleaned.push(worktree);
        } else {
          result.failed.push({
            worktree,
            error: removeResult.error || "Unknown error",
          });
        }
      }
    }

    return {
      success: true,
      data: result,
    };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Cleanup a specific session worktree
 */
export async function cleanupSessionWorktree(
  repoPath: string,
  config: WorktreeConfig,
  sessionId: string,
  options: Omit<CleanupOptions, "strategy"> = {}
): Promise<WorktreeResult<void>> {
  const { dryRun = false, force = false } = options;

  const worktrees = await listSessionWorktrees(repoPath, config);
  const worktree = worktrees.find((w) => w.sessionId === sessionId);

  if (!worktree) {
    return {
      success: false,
      error: `Session worktree not found: ${sessionId}`,
    };
  }

  if (dryRun) {
    return { success: true };
  }

  return removeWorktree(repoPath, worktree.path, {
    force,
    deleteBranch: true,
  });
}

/**
 * Cleanup all merged worktrees
 */
export async function cleanupMergedWorktrees(
  repoPath: string,
  config: WorktreeConfig,
  options: { dryRun?: boolean; force?: boolean } = {}
): Promise<WorktreeResult<CleanupResult>> {
  return cleanupWorktrees(repoPath, config, {
    strategy: "post-merge",
    ...options,
  });
}

/**
 * Cleanup all stale worktrees
 */
export async function cleanupStaleWorktrees(
  repoPath: string,
  config: WorktreeConfig,
  options: { ttlMs?: number; dryRun?: boolean; force?: boolean } = {}
): Promise<WorktreeResult<CleanupResult>> {
  return cleanupWorktrees(repoPath, config, {
    strategy: "timeout",
    ...options,
  });
}

/**
 * Get cleanup candidates (worktrees that could be cleaned)
 */
export async function getCleanupCandidates(
  repoPath: string,
  config: WorktreeConfig
): Promise<{
  merged: SessionWorktree[];
  stale: SessionWorktree[];
  prunable: SessionWorktree[];
}> {
  const worktrees = await listSessionWorktrees(repoPath, config);
  const candidates = {
    merged: [] as SessionWorktree[],
    stale: [] as SessionWorktree[],
    prunable: [] as SessionWorktree[],
  };

  for (const worktree of worktrees) {
    if (worktree.isPrunable) {
      candidates.prunable.push(worktree);
      continue;
    }

    const merged = await isMerged(
      repoPath,
      worktree,
      worktree.baseBranch || "main"
    );
    if (merged) {
      candidates.merged.push(worktree);
    }

    const stale = await isStale(worktree, config.defaultTtlMs);
    if (stale) {
      candidates.stale.push(worktree);
    }
  }

  return candidates;
}
