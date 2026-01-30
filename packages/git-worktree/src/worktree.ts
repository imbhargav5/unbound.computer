import { mkdir, rm, stat } from "node:fs/promises";
import { join, resolve } from "node:path";
import {
  branchExists,
  deleteBranch,
  GitError,
  getDefaultBranch,
  git,
  isGitRepository,
} from "./git.js";
import type {
  CreateWorktreeOptions,
  RemoveWorktreeOptions,
  SessionWorktree,
  WorktreeConfig,
  WorktreeInfo,
  WorktreeResult,
} from "./types.js";

/**
 * Parse git worktree list --porcelain output
 */
function parseWorktreeList(output: string): WorktreeInfo[] {
  const worktrees: WorktreeInfo[] = [];
  const blocks = output.split("\n\n").filter(Boolean);

  for (const block of blocks) {
    const lines = block.split("\n");
    const info: Partial<WorktreeInfo> = {
      isMain: false,
      isLocked: false,
      isPrunable: false,
    };

    for (const line of lines) {
      if (line.startsWith("worktree ")) {
        info.path = line.slice(9);
      } else if (line.startsWith("HEAD ")) {
        info.head = line.slice(5);
      } else if (line.startsWith("branch ")) {
        info.branch = line.slice(7).replace("refs/heads/", "");
      } else if (line === "bare") {
        info.isMain = true;
      } else if (line === "detached") {
        info.branch = null;
      } else if (line === "locked") {
        info.isLocked = true;
      } else if (line.startsWith("locked ")) {
        info.isLocked = true;
        info.lockReason = line.slice(7);
      } else if (line === "prunable") {
        info.isPrunable = true;
      } else if (line.startsWith("prunable ")) {
        info.isPrunable = true;
        info.pruneReason = line.slice(9);
      }
    }

    // First worktree is always the main one
    if (worktrees.length === 0) {
      info.isMain = true;
    }

    if (info.path && info.head) {
      worktrees.push(info as WorktreeInfo);
    }
  }

  return worktrees;
}

/**
 * List all worktrees for a repository
 */
export async function listWorktrees(repoPath: string): Promise<WorktreeInfo[]> {
  const result = await git(["worktree", "list", "--porcelain"], {
    cwd: repoPath,
  });
  return parseWorktreeList(result.stdout);
}

/**
 * Get a specific worktree by path
 */
export async function getWorktree(
  repoPath: string,
  worktreePath: string
): Promise<WorktreeInfo | null> {
  const worktrees = await listWorktrees(repoPath);
  const absolutePath = resolve(worktreePath);
  return worktrees.find((w) => resolve(w.path) === absolutePath) || null;
}

/**
 * Create a new worktree for a session
 */
export async function createWorktree(
  repoPath: string,
  config: WorktreeConfig,
  options: CreateWorktreeOptions
): Promise<WorktreeResult<SessionWorktree>> {
  const {
    sessionId,
    baseBranch,
    branchName,
    force = false,
    checkout = true,
  } = options;

  try {
    // Validate repository
    if (!(await isGitRepository(repoPath))) {
      return {
        success: false,
        error: `Not a git repository: ${repoPath}`,
      };
    }

    // Determine base branch
    const base = baseBranch || (await getDefaultBranch(repoPath));

    // Generate branch name
    const newBranch = branchName || `${config.branchPrefix}${sessionId}`;

    // Check if branch already exists
    if (!force && (await branchExists(repoPath, newBranch))) {
      return {
        success: false,
        error: `Branch already exists: ${newBranch}`,
      };
    }

    // Create worktree directory path
    const worktreePath = join(config.worktreesDir, sessionId);

    // Ensure worktrees directory exists
    await mkdir(config.worktreesDir, { recursive: true });

    // Check if worktree path already exists
    try {
      await stat(worktreePath);
      if (!force) {
        return {
          success: false,
          error: `Worktree path already exists: ${worktreePath}`,
        };
      }
      // Remove existing directory if force
      await rm(worktreePath, { recursive: true, force: true });
    } catch {
      // Path doesn't exist, which is good
    }

    // Create the worktree
    const args = ["worktree", "add"];

    if (!checkout) {
      args.push("--no-checkout");
    }

    // Add new branch flag
    args.push("-b", newBranch);

    // Add path and base branch
    args.push(worktreePath, base);

    await git(args, { cwd: repoPath });

    // Get worktree info
    const worktreeInfo = await getWorktree(repoPath, worktreePath);

    if (!worktreeInfo) {
      return {
        success: false,
        error: "Failed to create worktree",
      };
    }

    const now = new Date();
    const sessionWorktree: SessionWorktree = {
      ...worktreeInfo,
      sessionId,
      createdAt: now,
      lastActivityAt: now,
      baseBranch: base,
      repositoryPath: repoPath,
    };

    return {
      success: true,
      data: sessionWorktree,
    };
  } catch (error) {
    const message =
      error instanceof GitError
        ? error.stderr
        : error instanceof Error
          ? error.message
          : String(error);
    return {
      success: false,
      error: message,
    };
  }
}

/**
 * Remove a worktree
 */
export async function removeWorktree(
  repoPath: string,
  worktreePath: string,
  options: RemoveWorktreeOptions = {}
): Promise<WorktreeResult<void>> {
  const { force = false, deleteBranch: shouldDeleteBranch = true } = options;

  try {
    // Get worktree info first
    const worktree = await getWorktree(repoPath, worktreePath);

    if (!worktree) {
      return {
        success: false,
        error: `Worktree not found: ${worktreePath}`,
      };
    }

    if (worktree.isMain) {
      return {
        success: false,
        error: "Cannot remove main worktree",
      };
    }

    const branchToDelete = worktree.branch;

    // Remove the worktree
    const args = ["worktree", "remove"];
    if (force) {
      args.push("--force");
    }
    args.push(worktreePath);

    await git(args, { cwd: repoPath });

    // Delete the branch if requested
    if (shouldDeleteBranch && branchToDelete) {
      try {
        await deleteBranch(repoPath, branchToDelete, force);
      } catch {
        // Ignore branch deletion errors
      }
    }

    return { success: true };
  } catch (error) {
    const message =
      error instanceof GitError
        ? error.stderr
        : error instanceof Error
          ? error.message
          : String(error);
    return {
      success: false,
      error: message,
    };
  }
}

/**
 * Lock a worktree to prevent pruning
 */
export async function lockWorktree(
  repoPath: string,
  worktreePath: string,
  reason?: string
): Promise<WorktreeResult<void>> {
  try {
    const args = ["worktree", "lock"];
    if (reason) {
      args.push("--reason", reason);
    }
    args.push(worktreePath);

    await git(args, { cwd: repoPath });
    return { success: true };
  } catch (error) {
    const message =
      error instanceof GitError
        ? error.stderr
        : error instanceof Error
          ? error.message
          : String(error);
    return {
      success: false,
      error: message,
    };
  }
}

/**
 * Unlock a worktree
 */
export async function unlockWorktree(
  repoPath: string,
  worktreePath: string
): Promise<WorktreeResult<void>> {
  try {
    await git(["worktree", "unlock", worktreePath], { cwd: repoPath });
    return { success: true };
  } catch (error) {
    const message =
      error instanceof GitError
        ? error.stderr
        : error instanceof Error
          ? error.message
          : String(error);
    return {
      success: false,
      error: message,
    };
  }
}

/**
 * Prune stale worktree information
 */
export async function pruneWorktrees(
  repoPath: string,
  dryRun = false
): Promise<WorktreeResult<string[]>> {
  try {
    const args = ["worktree", "prune"];
    if (dryRun) {
      args.push("--dry-run");
    }
    args.push("-v");

    const result = await git(args, { cwd: repoPath });

    // Parse pruned worktrees from output
    const pruned: string[] = [];
    for (const line of result.stdout.split("\n")) {
      if (line.startsWith("Removing")) {
        const match = line.match(/Removing (.+):/);
        if (match) {
          pruned.push(match[1]);
        }
      }
    }

    return {
      success: true,
      data: pruned,
    };
  } catch (error) {
    const message =
      error instanceof GitError
        ? error.stderr
        : error instanceof Error
          ? error.message
          : String(error);
    return {
      success: false,
      error: message,
    };
  }
}

/**
 * List session worktrees (worktrees in the configured worktrees directory)
 */
export async function listSessionWorktrees(
  repoPath: string,
  config: WorktreeConfig
): Promise<SessionWorktree[]> {
  const allWorktrees = await listWorktrees(repoPath);
  const sessionWorktrees: SessionWorktree[] = [];

  for (const worktree of allWorktrees) {
    // Check if this worktree is in our worktrees directory
    if (!worktree.path.startsWith(config.worktreesDir)) {
      continue;
    }

    // Extract session ID from path
    const sessionId = worktree.path.slice(config.worktreesDir.length + 1);

    // Get creation time from directory
    let createdAt = new Date();
    let lastActivityAt = new Date();

    try {
      const stats = await stat(worktree.path);
      createdAt = stats.birthtime;
      lastActivityAt = stats.mtime;
    } catch {
      // Ignore stat errors
    }

    // Determine base branch from branch name
    const baseBranch = worktree.branch?.replace(config.branchPrefix, "") || "";

    sessionWorktrees.push({
      ...worktree,
      sessionId,
      createdAt,
      lastActivityAt,
      baseBranch,
      repositoryPath: repoPath,
    });
  }

  return sessionWorktrees;
}

/**
 * Get worktree for a specific session
 */
export async function getSessionWorktree(
  repoPath: string,
  config: WorktreeConfig,
  sessionId: string
): Promise<SessionWorktree | null> {
  const worktreePath = join(config.worktreesDir, sessionId);
  const worktree = await getWorktree(repoPath, worktreePath);

  if (!worktree) {
    return null;
  }

  let createdAt = new Date();
  let lastActivityAt = new Date();

  try {
    const stats = await stat(worktree.path);
    createdAt = stats.birthtime;
    lastActivityAt = stats.mtime;
  } catch {
    // Ignore stat errors
  }

  const baseBranch = worktree.branch?.replace(config.branchPrefix, "") || "";

  return {
    ...worktree,
    sessionId,
    createdAt,
    lastActivityAt,
    baseBranch,
    repositoryPath: repoPath,
  };
}
