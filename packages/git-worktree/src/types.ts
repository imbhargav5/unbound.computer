import { z } from "zod";

/**
 * Worktree status
 */
export type WorktreeStatus = "active" | "stale" | "locked" | "prunable";

/**
 * Worktree information
 */
export interface WorktreeInfo {
  /** Branch name (if checked out) */
  branch: string | null;
  /** HEAD commit SHA */
  head: string;
  /** Whether the worktree is locked */
  isLocked: boolean;
  /** Whether this is the main worktree */
  isMain: boolean;
  /** Whether the worktree can be pruned */
  isPrunable: boolean;
  /** Lock reason if locked */
  lockReason?: string;
  /** Absolute path to the worktree directory */
  path: string;
  /** Prune reason if prunable */
  pruneReason?: string;
}

/**
 * Session worktree - worktree created for an Unbound session
 */
export interface SessionWorktree extends WorktreeInfo {
  /** Base branch the worktree was created from */
  baseBranch: string;
  /** When the worktree was created */
  createdAt: Date;
  /** Last activity timestamp */
  lastActivityAt: Date;
  /** Repository path (main worktree) */
  repositoryPath: string;
  /** Session ID this worktree belongs to */
  sessionId: string;
}

/**
 * Worktree creation options
 */
export interface CreateWorktreeOptions {
  /** Base branch to create from (default: current branch or main/master) */
  baseBranch?: string;
  /** Custom branch name (default: unbound/<sessionId>) */
  branchName?: string;
  /** Checkout after creation */
  checkout?: boolean;
  /** Force creation even if branch exists */
  force?: boolean;
  /** Session ID for naming */
  sessionId: string;
  /** Track remote branch */
  track?: boolean;
}

/**
 * Worktree removal options
 */
export interface RemoveWorktreeOptions {
  /** Also delete the branch */
  deleteBranch?: boolean;
  /** Force removal even if there are uncommitted changes */
  force?: boolean;
}

/**
 * Cleanup strategy
 */
export type CleanupStrategy = "manual" | "post-merge" | "timeout" | "on-demand";

/**
 * Cleanup options
 */
export interface CleanupOptions {
  /** Dry run - don't actually remove anything */
  dryRun?: boolean;
  /** Force removal of locked worktrees */
  force?: boolean;
  /** Strategy to use */
  strategy: CleanupStrategy;
  /** TTL in milliseconds for timeout strategy */
  ttlMs?: number;
}

/**
 * Git repository information
 */
export interface RepositoryInfo {
  /** Common git directory (for worktrees) */
  commonDir: string;
  /** Current branch */
  currentBranch: string | null;
  /** Git directory path */
  gitDir: string;
  /** Current HEAD commit */
  head: string;
  /** Whether there are uncommitted changes */
  isDirty: boolean;
  /** Whether this is a worktree */
  isWorktree: boolean;
  /** Remote URL (origin) */
  remoteUrl: string | null;
  /** Root path of the repository */
  rootPath: string;
}

/**
 * Branch information
 */
export interface BranchInfo {
  /** Ahead/behind counts */
  ahead?: number;
  behind?: number;
  /** Commit SHA */
  commit: string;
  /** Whether this is the current branch */
  isCurrent: boolean;
  /** Branch name */
  name: string;
  /** Full ref name */
  refName: string;
  /** Upstream branch if tracking */
  upstream?: string;
}

/**
 * Worktree manager configuration
 */
export const WorktreeConfigSchema = z.object({
  /** Base directory for worktrees */
  worktreesDir: z.string(),
  /** Default TTL for timeout cleanup (ms) */
  defaultTtlMs: z.number().default(7 * 24 * 60 * 60 * 1000), // 7 days
  /** Branch prefix for session branches */
  branchPrefix: z.string().default("unbound/"),
  /** Whether to auto-cleanup merged branches */
  autoCleanupMerged: z.boolean().default(true),
});

export type WorktreeConfig = z.infer<typeof WorktreeConfigSchema>;

/**
 * Worktree operation result
 */
export interface WorktreeResult<T> {
  data?: T;
  error?: string;
  success: boolean;
}

/**
 * Disk usage information
 */
export interface DiskUsage {
  /** Human-readable size */
  humanReadable: string;
  /** Total size in bytes */
  totalBytes: number;
}
