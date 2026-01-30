import { stat } from "node:fs/promises";
import { resolve } from "node:path";
import {
  getCommonDir,
  getCurrentBranch,
  getGitDir,
  getHead,
  getRemoteUrl,
  getRepositoryRoot,
  isDirty,
  isGitRepository,
} from "./git.js";
import type { DiskUsage, RepositoryInfo } from "./types.js";

/**
 * Get complete repository information
 */
export async function getRepositoryInfo(path: string): Promise<RepositoryInfo> {
  if (!(await isGitRepository(path))) {
    throw new Error(`Not a git repository: ${path}`);
  }

  const rootPath = await getRepositoryRoot(path);
  const gitDir = await getGitDir(path);
  const commonDir = await getCommonDir(path);

  // Determine if this is a worktree by comparing git dir and common dir
  const resolvedGitDir = resolve(rootPath, gitDir);
  const resolvedCommonDir = resolve(rootPath, commonDir);
  const isWorktree = resolvedGitDir !== resolvedCommonDir;

  const [currentBranch, head, remoteUrl, dirty] = await Promise.all([
    getCurrentBranch(path),
    getHead(path),
    getRemoteUrl(path),
    isDirty(path),
  ]);

  return {
    rootPath,
    gitDir: resolvedGitDir,
    commonDir: resolvedCommonDir,
    isWorktree,
    currentBranch,
    head,
    remoteUrl,
    isDirty: dirty,
  };
}

/**
 * Validate that a path is a valid git repository for worktree operations
 */
export async function validateRepository(path: string): Promise<{
  valid: boolean;
  error?: string;
  info?: RepositoryInfo;
}> {
  try {
    const info = await getRepositoryInfo(path);

    // Worktrees can only be created from the main worktree
    if (info.isWorktree) {
      return {
        valid: false,
        error:
          "Cannot create worktrees from a worktree. Use the main repository.",
        info,
      };
    }

    return {
      valid: true,
      info,
    };
  } catch (error) {
    return {
      valid: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Get the main repository path from a worktree
 */
export async function getMainRepositoryPath(path: string): Promise<string> {
  const info = await getRepositoryInfo(path);

  if (!info.isWorktree) {
    return info.rootPath;
  }

  // The common dir points to the main repository's .git directory
  // We need to get the parent of that
  const commonDir = info.commonDir;

  // If commonDir ends with .git, return its parent
  if (commonDir.endsWith(".git")) {
    return resolve(commonDir, "..");
  }

  // Otherwise, read the gitdir file to find the main repo
  // This shouldn't normally happen, but handle it just in case
  return resolve(commonDir, "..");
}

/**
 * Calculate disk usage for a directory
 */
export async function getDiskUsage(path: string): Promise<DiskUsage> {
  const { exec } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const execAsync = promisify(exec);

  try {
    // Use du command on Unix-like systems
    const result = await execAsync(
      `du -sb "${path}" 2>/dev/null || du -sk "${path}"`
    );
    const parts = result.stdout.trim().split(/\s+/);
    let totalBytes = Number.parseInt(parts[0], 10);

    // du -sk returns KB, du -sb returns bytes
    if (!result.stdout.includes("-sb")) {
      totalBytes *= 1024;
    }

    return {
      totalBytes,
      humanReadable: formatBytes(totalBytes),
    };
  } catch {
    // Fallback: try to stat the directory
    const stats = await stat(path);
    return {
      totalBytes: stats.size,
      humanReadable: formatBytes(stats.size),
    };
  }
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

/**
 * Check if there's enough disk space for a worktree
 */
export async function checkDiskSpace(
  path: string,
  requiredBytes: number
): Promise<{ sufficient: boolean; available: number }> {
  const { exec } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const execAsync = promisify(exec);

  try {
    // Use df command to get available space
    const result = await execAsync(
      `df -B1 "${path}" 2>/dev/null || df -k "${path}"`
    );
    const lines = result.stdout.trim().split("\n");

    if (lines.length < 2) {
      return { sufficient: true, available: 0 };
    }

    const parts = lines[1].split(/\s+/);
    let available = Number.parseInt(parts[3], 10);

    // df -k returns KB
    if (!result.stdout.includes("-B1")) {
      available *= 1024;
    }

    return {
      sufficient: available >= requiredBytes,
      available,
    };
  } catch {
    // If we can't check, assume it's fine
    return { sufficient: true, available: 0 };
  }
}
