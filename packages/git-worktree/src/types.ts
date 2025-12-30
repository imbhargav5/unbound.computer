import { z } from "zod";

/**
 * Worktree status
 */
export type WorktreeStatus = "active" | "stale" | "locked" | "prunable";

/**
 * Worktree information
 */
export interface WorktreeInfo {
  /** Absolute path to the worktree directory */
  path: string;
  /** HEAD commit SHA */
  head: string;
  /** Branch name (if checked out) */
  branch: string | null;
  /** Whether this is the main worktree */
  isMain: boolean;
  /** Whether the worktree is locked */
  isLocked: boolean;
  /** Lock reason if locked */
  lockReason?: string;
  /** Whether the worktree can be pruned */
  isPrunable: boolean;
  /** Prune reason if prunable */
  pruneReason?: string;
}

/**
 * Session worktree - worktree created for an Unbound session
 */
export interface SessionWorktree extends WorktreeInfo {
  /** Session ID this worktree belongs to */
  sessionId: string;
  /** When the worktree was created */
  createdAt: Date;
  /** Last activity timestamp */
  lastActivityAt: Date;
  /** Base branch the worktree was created from */
  baseBranch: string;
  /** Repository path (main worktree) */
  repositoryPath: string;
}

/**
 * Worktree creation options
 */
export interface CreateWorktreeOptions {
  /** Session ID for naming */
  sessionId: string;
  /** Base branch to create from (default: current branch or main/master) */
  baseBranch?: string;
  /** Custom branch name (default: unbound/<sessionId>) */
  branchName?: string;
  /** Force creation even if branch exists */
  force?: boolean;
  /** Track remote branch */
  track?: boolean;
  /** Checkout after creation */
  checkout?: boolean;
}

/**
 * Worktree removal options
 */
export interface RemoveWorktreeOptions {
  /** Force removal even if there are uncommitted changes */
  force?: boolean;
  /** Also delete the branch */
  deleteBranch?: boolean;
}

/**
 * Cleanup strategy
 */
export type CleanupStrategy = "manual" | "post-merge" | "timeout" | "on-demand";

/**
 * Cleanup options
 */
export interface CleanupOptions {
  /** Strategy to use */
  strategy: CleanupStrategy;
  /** TTL in milliseconds for timeout strategy */
  ttlMs?: number;
  /** Dry run - don't actually remove anything */
  dryRun?: boolean;
  /** Force removal of locked worktrees */
  force?: boolean;
}

/**
 * Git repository information
 */
export interface RepositoryInfo {
  /** Root path of the repository */
  rootPath: string;
  /** Git directory path */
  gitDir: string;
  /** Common git directory (for worktrees) */
  commonDir: string;
  /** Whether this is a worktree */
  isWorktree: boolean;
  /** Current branch */
  currentBranch: string | null;
  /** Current HEAD commit */
  head: string;
  /** Remote URL (origin) */
  remoteUrl: string | null;
  /** Whether there are uncommitted changes */
  isDirty: boolean;
}

/**
 * Branch information
 */
export interface BranchInfo {
  /** Branch name */
  name: string;
  /** Full ref name */
  refName: string;
  /** Commit SHA */
  commit: string;
  /** Whether this is the current branch */
  isCurrent: boolean;
  /** Upstream branch if tracking */
  upstream?: string;
  /** Ahead/behind counts */
  ahead?: number;
  behind?: number;
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
  success: boolean;
  data?: T;
  error?: string;
}

/**
 * Disk usage information
 */
export interface DiskUsage {
  /** Total size in bytes */
  totalBytes: number;
  /** Human-readable size */
  humanReadable: string;
}
