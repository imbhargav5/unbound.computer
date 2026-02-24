import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);

/**
 * Git command execution options
 */
interface GitExecOptions {
  /** Working directory */
  cwd?: string;
  /** Environment variables */
  env?: Record<string, string>;
  /** Timeout in milliseconds */
  timeout?: number;
}

/**
 * Git command result
 */
interface GitResult {
  stderr: string;
  stdout: string;
}

/**
 * Execute a git command
 */
export async function git(
  args: string[],
  options: GitExecOptions = {}
): Promise<GitResult> {
  const { cwd, env, timeout = 30_000 } = options;

  const command = `git ${args.join(" ")}`;

  try {
    const result = await execAsync(command, {
      cwd,
      env: { ...process.env, ...env },
      timeout,
      maxBuffer: 10 * 1024 * 1024, // 10MB
    });

    return {
      stdout: result.stdout.trim(),
      stderr: result.stderr.trim(),
    };
  } catch (error) {
    const execError = error as Error & { stdout?: string; stderr?: string };
    throw new GitError(
      `Git command failed: ${command}`,
      execError.stderr || execError.message,
      args
    );
  }
}

/**
 * Check if a path is inside a git repository
 */
export async function isGitRepository(path: string): Promise<boolean> {
  try {
    await git(["rev-parse", "--git-dir"], { cwd: path });
    return true;
  } catch {
    return false;
  }
}

/**
 * Get the root path of a git repository
 */
export async function getRepositoryRoot(path: string): Promise<string> {
  const result = await git(["rev-parse", "--show-toplevel"], { cwd: path });
  return result.stdout;
}

/**
 * Get the git directory path
 */
export async function getGitDir(path: string): Promise<string> {
  const result = await git(["rev-parse", "--git-dir"], { cwd: path });
  return result.stdout;
}

/**
 * Get the common git directory (shared across worktrees)
 */
export async function getCommonDir(path: string): Promise<string> {
  const result = await git(["rev-parse", "--git-common-dir"], { cwd: path });
  return result.stdout;
}

/**
 * Get the current branch name
 */
export async function getCurrentBranch(path: string): Promise<string | null> {
  try {
    const result = await git(["rev-parse", "--abbrev-ref", "HEAD"], {
      cwd: path,
    });
    return result.stdout === "HEAD" ? null : result.stdout;
  } catch {
    return null;
  }
}

/**
 * Get the current HEAD commit SHA
 */
export async function getHead(path: string): Promise<string> {
  const result = await git(["rev-parse", "HEAD"], { cwd: path });
  return result.stdout;
}

/**
 * Get the remote URL for a remote
 */
export async function getRemoteUrl(
  path: string,
  remote = "origin"
): Promise<string | null> {
  try {
    const result = await git(["remote", "get-url", remote], { cwd: path });
    return result.stdout;
  } catch {
    return null;
  }
}

/**
 * Check if there are uncommitted changes
 */
export async function isDirty(path: string): Promise<boolean> {
  try {
    const result = await git(["status", "--porcelain"], { cwd: path });
    return result.stdout.length > 0;
  } catch {
    return false;
  }
}

/**
 * Check if a branch exists
 */
export async function branchExists(
  path: string,
  branchName: string
): Promise<boolean> {
  try {
    await git(["rev-parse", "--verify", `refs/heads/${branchName}`], {
      cwd: path,
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * Create a new branch
 */
export async function createBranch(
  path: string,
  branchName: string,
  startPoint?: string
): Promise<void> {
  const args = ["branch", branchName];
  if (startPoint) {
    args.push(startPoint);
  }
  await git(args, { cwd: path });
}

/**
 * Delete a branch
 */
export async function deleteBranch(
  path: string,
  branchName: string,
  force = false
): Promise<void> {
  const flag = force ? "-D" : "-d";
  await git(["branch", flag, branchName], { cwd: path });
}

/**
 * Get the default branch (main or master)
 */
export async function getDefaultBranch(path: string): Promise<string> {
  // Try to get from remote HEAD
  try {
    const result = await git(["symbolic-ref", "refs/remotes/origin/HEAD"], {
      cwd: path,
    });
    const match = result.stdout.match(/refs\/remotes\/origin\/(.+)/);
    if (match) {
      return match[1];
    }
  } catch {
    // Ignore
  }

  // Check if main or master exists
  if (await branchExists(path, "main")) {
    return "main";
  }
  if (await branchExists(path, "master")) {
    return "master";
  }

  // Fall back to current branch
  const current = await getCurrentBranch(path);
  return current || "main";
}

/**
 * Check if a commit is an ancestor of another
 */
export async function isAncestor(
  path: string,
  ancestor: string,
  descendant: string
): Promise<boolean> {
  try {
    await git(["merge-base", "--is-ancestor", ancestor, descendant], {
      cwd: path,
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * Fetch from remote
 */
export async function fetch(
  path: string,
  remote = "origin",
  prune = false
): Promise<void> {
  const args = ["fetch", remote];
  if (prune) {
    args.push("--prune");
  }
  await git(args, { cwd: path });
}

/**
 * Git error class
 */
export class GitError extends Error {
  constructor(
    message: string,
    public readonly stderr: string,
    public readonly args: string[]
  ) {
    super(message);
    this.name = "GitError";
  }
}
