import { homedir } from "node:os";
import { join } from "node:path";
import type { CleanupResult } from "./cleanup.js";
import {
  cleanupMergedWorktrees,
  cleanupSessionWorktree,
  cleanupStaleWorktrees,
  cleanupWorktrees,
  getCleanupCandidates,
} from "./cleanup.js";
import {
  checkDiskSpace,
  getDiskUsage,
  getMainRepositoryPath,
  getRepositoryInfo,
  validateRepository,
} from "./repository.js";
import type {
  CleanupOptions,
  CreateWorktreeOptions,
  DiskUsage,
  RemoveWorktreeOptions,
  RepositoryInfo,
  SessionWorktree,
  WorktreeConfig,
  WorktreeInfo,
  WorktreeResult,
} from "./types.js";
import { WorktreeConfigSchema } from "./types.js";
import {
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

/**
 * Default worktrees directory
 */
const DEFAULT_WORKTREES_DIR = join(homedir(), ".unbound", "worktrees");

/**
 * Worktree Manager - high-level API for managing git worktrees
 */
export class WorktreeManager {
  private config: WorktreeConfig;
  private repoPath: string;

  constructor(repoPath: string, config?: Partial<WorktreeConfig>) {
    this.repoPath = repoPath;
    this.config = WorktreeConfigSchema.parse({
      worktreesDir: DEFAULT_WORKTREES_DIR,
      ...config,
    });
  }

  /**
   * Get the configuration
   */
  getConfig(): WorktreeConfig {
    return { ...this.config };
  }

  /**
   * Get the repository path
   */
  getRepoPath(): string {
    return this.repoPath;
  }

  /**
   * Validate the repository for worktree operations
   */
  async validate(): Promise<{
    valid: boolean;
    error?: string;
    info?: RepositoryInfo;
  }> {
    return validateRepository(this.repoPath);
  }

  /**
   * Get repository information
   */
  async getRepositoryInfo(): Promise<RepositoryInfo> {
    return getRepositoryInfo(this.repoPath);
  }

  /**
   * List all worktrees in the repository
   */
  async listWorktrees(): Promise<WorktreeInfo[]> {
    return listWorktrees(this.repoPath);
  }

  /**
   * List session worktrees (managed by Unbound)
   */
  async listSessionWorktrees(): Promise<SessionWorktree[]> {
    return listSessionWorktrees(this.repoPath, this.config);
  }

  /**
   * Get a specific worktree by path
   */
  async getWorktree(worktreePath: string): Promise<WorktreeInfo | null> {
    return getWorktree(this.repoPath, worktreePath);
  }

  /**
   * Get a session worktree by session ID
   */
  async getSessionWorktree(sessionId: string): Promise<SessionWorktree | null> {
    return getSessionWorktree(this.repoPath, this.config, sessionId);
  }

  /**
   * Create a new worktree for a session
   */
  async createWorktree(
    options: CreateWorktreeOptions
  ): Promise<WorktreeResult<SessionWorktree>> {
    // Validate repository first
    const validation = await this.validate();
    if (!validation.valid) {
      return {
        success: false,
        error: validation.error,
      };
    }

    return createWorktree(this.repoPath, this.config, options);
  }

  /**
   * Remove a worktree
   */
  async removeWorktree(
    worktreePath: string,
    options?: RemoveWorktreeOptions
  ): Promise<WorktreeResult<void>> {
    return removeWorktree(this.repoPath, worktreePath, options);
  }

  /**
   * Remove a session worktree by session ID
   */
  async removeSessionWorktree(
    sessionId: string,
    options?: RemoveWorktreeOptions
  ): Promise<WorktreeResult<void>> {
    const worktree = await this.getSessionWorktree(sessionId);
    if (!worktree) {
      return {
        success: false,
        error: `Session worktree not found: ${sessionId}`,
      };
    }
    return removeWorktree(this.repoPath, worktree.path, options);
  }

  /**
   * Lock a worktree to prevent cleanup
   */
  async lockWorktree(
    worktreePath: string,
    reason?: string
  ): Promise<WorktreeResult<void>> {
    return lockWorktree(this.repoPath, worktreePath, reason);
  }

  /**
   * Lock a session worktree
   */
  async lockSessionWorktree(
    sessionId: string,
    reason?: string
  ): Promise<WorktreeResult<void>> {
    const worktree = await this.getSessionWorktree(sessionId);
    if (!worktree) {
      return {
        success: false,
        error: `Session worktree not found: ${sessionId}`,
      };
    }
    return lockWorktree(this.repoPath, worktree.path, reason);
  }

  /**
   * Unlock a worktree
   */
  async unlockWorktree(worktreePath: string): Promise<WorktreeResult<void>> {
    return unlockWorktree(this.repoPath, worktreePath);
  }

  /**
   * Unlock a session worktree
   */
  async unlockSessionWorktree(
    sessionId: string
  ): Promise<WorktreeResult<void>> {
    const worktree = await this.getSessionWorktree(sessionId);
    if (!worktree) {
      return {
        success: false,
        error: `Session worktree not found: ${sessionId}`,
      };
    }
    return unlockWorktree(this.repoPath, worktree.path);
  }

  /**
   * Prune stale worktree references
   */
  async prune(dryRun = false): Promise<WorktreeResult<string[]>> {
    return pruneWorktrees(this.repoPath, dryRun);
  }

  /**
   * Cleanup worktrees using a specific strategy
   */
  async cleanup(
    options: CleanupOptions
  ): Promise<WorktreeResult<CleanupResult>> {
    return cleanupWorktrees(this.repoPath, this.config, options);
  }

  /**
   * Cleanup a specific session worktree
   */
  async cleanupSession(
    sessionId: string,
    options?: { dryRun?: boolean; force?: boolean }
  ): Promise<WorktreeResult<void>> {
    return cleanupSessionWorktree(
      this.repoPath,
      this.config,
      sessionId,
      options
    );
  }

  /**
   * Cleanup all merged worktrees
   */
  async cleanupMerged(options?: {
    dryRun?: boolean;
    force?: boolean;
  }): Promise<WorktreeResult<CleanupResult>> {
    return cleanupMergedWorktrees(this.repoPath, this.config, options);
  }

  /**
   * Cleanup all stale worktrees
   */
  async cleanupStale(options?: {
    ttlMs?: number;
    dryRun?: boolean;
    force?: boolean;
  }): Promise<WorktreeResult<CleanupResult>> {
    return cleanupStaleWorktrees(this.repoPath, this.config, options);
  }

  /**
   * Get worktrees that are candidates for cleanup
   */
  async getCleanupCandidates(): Promise<{
    merged: SessionWorktree[];
    stale: SessionWorktree[];
    prunable: SessionWorktree[];
  }> {
    return getCleanupCandidates(this.repoPath, this.config);
  }

  /**
   * Get disk usage for all session worktrees
   */
  async getDiskUsage(): Promise<Map<string, DiskUsage>> {
    const worktrees = await this.listSessionWorktrees();
    const usage = new Map<string, DiskUsage>();

    for (const worktree of worktrees) {
      try {
        const du = await getDiskUsage(worktree.path);
        usage.set(worktree.sessionId, du);
      } catch {
        // Ignore errors for individual worktrees
      }
    }

    return usage;
  }

  /**
   * Get total disk usage for all session worktrees
   */
  async getTotalDiskUsage(): Promise<DiskUsage> {
    const usage = await this.getDiskUsage();
    let totalBytes = 0;

    for (const du of usage.values()) {
      totalBytes += du.totalBytes;
    }

    return {
      totalBytes,
      humanReadable: formatBytes(totalBytes),
    };
  }

  /**
   * Check if there's enough disk space for a new worktree
   */
  async checkDiskSpace(requiredBytes: number): Promise<{
    sufficient: boolean;
    available: number;
  }> {
    return checkDiskSpace(this.config.worktreesDir, requiredBytes);
  }

  /**
   * Get summary statistics
   */
  async getStats(): Promise<{
    totalWorktrees: number;
    sessionWorktrees: number;
    lockedWorktrees: number;
    prunableWorktrees: number;
    diskUsage: DiskUsage;
  }> {
    const [allWorktrees, sessionWorktrees, diskUsage] = await Promise.all([
      this.listWorktrees(),
      this.listSessionWorktrees(),
      this.getTotalDiskUsage(),
    ]);

    const lockedWorktrees = sessionWorktrees.filter((w) => w.isLocked).length;
    const prunableWorktrees = sessionWorktrees.filter(
      (w) => w.isPrunable
    ).length;

    return {
      totalWorktrees: allWorktrees.length,
      sessionWorktrees: sessionWorktrees.length,
      lockedWorktrees,
      prunableWorktrees,
      diskUsage,
    };
  }
}

/**
 * Create a worktree manager for a repository
 */
export function createWorktreeManager(
  repoPath: string,
  config?: Partial<WorktreeConfig>
): WorktreeManager {
  return new WorktreeManager(repoPath, config);
}

/**
 * Create a worktree manager, resolving to main repository if in a worktree
 */
export async function createWorktreeManagerFromPath(
  path: string,
  config?: Partial<WorktreeConfig>
): Promise<WorktreeManager> {
  const mainPath = await getMainRepositoryPath(path);
  return new WorktreeManager(mainPath, config);
}

/**
 * Format bytes as human-readable string
 */
function formatBytes(bytes: number): string {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let unitIndex = 0;
  let size = bytes;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }

  return `${size.toFixed(1)} ${units[unitIndex]}`;
}
