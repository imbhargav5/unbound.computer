import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);

interface GitRepoInfo {
  isGitRepo: boolean;
  rootPath?: string;
  remoteUrl?: string;
  defaultBranch?: string;
  currentBranch?: string;
  isWorktree: boolean;
  worktreeBranch?: string;
  parentPath?: string;
}

/**
 * Execute a git command and return stdout
 */
async function git(
  command: string,
  cwd: string
): Promise<{ stdout: string; stderr: string } | null> {
  try {
    return await execAsync(`git ${command}`, { cwd });
  } catch {
    return null;
  }
}

/**
 * Get git repository information for a directory
 */
export async function getGitRepoInfo(directory: string): Promise<GitRepoInfo> {
  // Check if it's a git repo
  const revParse = await git("rev-parse --is-inside-work-tree", directory);
  if (!revParse || revParse.stdout.trim() !== "true") {
    return { isGitRepo: false, isWorktree: false };
  }

  // Get root path
  const rootResult = await git("rev-parse --show-toplevel", directory);
  const rootPath = rootResult?.stdout.trim();

  // Get remote URL
  const remoteResult = await git("config --get remote.origin.url", directory);
  const remoteUrl = remoteResult?.stdout.trim();

  // Get current branch
  const branchResult = await git("rev-parse --abbrev-ref HEAD", directory);
  const currentBranch = branchResult?.stdout.trim();

  // Get default branch (main or master)
  const defaultBranchResult = await git(
    "symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || echo refs/heads/main",
    directory
  );
  const defaultBranch =
    defaultBranchResult?.stdout.trim().replace("refs/remotes/origin/", "") ||
    "main";

  // Check if worktree
  const gitDirResult = await git("rev-parse --git-dir", directory);
  const commonDirResult = await git("rev-parse --git-common-dir", directory);

  const gitDir = gitDirResult?.stdout.trim();
  const commonDir = commonDirResult?.stdout.trim();

  const isWorktree = gitDir !== commonDir && gitDir !== ".git";

  // Get parent path for worktrees
  let parentPath: string | undefined;
  let worktreeBranch: string | undefined;

  if (isWorktree && commonDir) {
    // commonDir points to the parent repo's .git directory
    // Parent path is one level up from commonDir
    const parentGitDir = commonDir.replace(/\/\.git$/, "");
    const parentRootResult = await git(
      `--git-dir="${commonDir}" rev-parse --show-toplevel`,
      directory
    );
    parentPath = parentRootResult?.stdout.trim() || parentGitDir;
    worktreeBranch = currentBranch;
  }

  return {
    isGitRepo: true,
    rootPath,
    remoteUrl,
    defaultBranch,
    currentBranch,
    isWorktree,
    worktreeBranch,
    parentPath,
  };
}

/**
 * Get the repository name from the remote URL
 */
export function getRepoName(remoteUrl: string): string {
  // Handle SSH URLs: git@github.com:user/repo.git
  // Handle HTTPS URLs: https://github.com/user/repo.git
  const match = remoteUrl.match(/[:/]([^/]+\/[^/]+?)(?:\.git)?$/);
  return match ? match[1] : remoteUrl;
}
