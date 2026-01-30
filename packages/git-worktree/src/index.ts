// Types

// Cleanup types
export type { CleanupResult } from "./cleanup.js";
// Cleanup operations
export {
  cleanupMergedWorktrees,
  cleanupSessionWorktree,
  cleanupStaleWorktrees,
  cleanupWorktrees,
  getCleanupCandidates,
} from "./cleanup.js";
// Git utilities
export { GitError, git, isGitRepository } from "./git.js";
// Manager
export {
  createWorktreeManager,
  createWorktreeManagerFromPath,
  WorktreeManager,
} from "./manager.js";

// Repository utilities
export {
  checkDiskSpace,
  getDiskUsage,
  getMainRepositoryPath,
  getRepositoryInfo,
  validateRepository,
} from "./repository.js";
export type {
  BranchInfo,
  CleanupOptions,
  CleanupStrategy,
  CreateWorktreeOptions,
  DiskUsage,
  RemoveWorktreeOptions,
  RepositoryInfo,
  SessionWorktree,
  WorktreeConfig,
  WorktreeInfo,
  WorktreeResult,
  WorktreeStatus,
} from "./types.js";
export { WorktreeConfigSchema } from "./types.js";
// Worktree operations
export {
  createWorktree,
  getSessionWorktree,
  getWorktree,
  listSessionWorktrees,
  listWorktrees,
  lockWorktree,
  pruneWorktrees,
  removeWorktree,
  unlockWorktree,
} from "./worktree.js";
