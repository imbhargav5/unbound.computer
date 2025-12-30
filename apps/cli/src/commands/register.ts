import chalk from "chalk";
import ora from "ora";
import { credentials } from "../auth/index.js";
import { ApiClient } from "../client/index.js";
import { getGitRepoInfo, getRepoName, logger } from "../utils/index.js";

/**
 * Register command - register current directory as a project
 */
export async function registerCommand(): Promise<void> {
  // Check if linked
  const isLinked = await credentials.isLinked();
  if (!isLinked) {
    console.log(chalk.yellow("Device not linked. Run 'unbound link' first."));
    process.exit(1);
  }

  const cwd = process.cwd();
  const spinner = ora("Detecting repository...").start();

  try {
    // Get git repo info
    const repoInfo = await getGitRepoInfo(cwd);

    if (!repoInfo.isGitRepo) {
      spinner.fail("Not a git repository");
      console.log(
        chalk.yellow("\nThis command must be run from within a git repository.")
      );
      process.exit(1);
    }

    spinner.text = "Registering repository...";

    // Get credentials
    const apiKey = await credentials.getApiKey();
    const deviceId = await credentials.getDeviceId();

    if (!(apiKey && deviceId)) {
      spinner.fail("Missing credentials");
      process.exit(1);
    }

    const api = new ApiClient(apiKey, deviceId);

    // If this is a worktree, register parent first
    let parentRepositoryId: string | undefined;

    if (repoInfo.isWorktree && repoInfo.parentPath) {
      spinner.text = "Registering parent repository...";

      const parentInfo = await getGitRepoInfo(repoInfo.parentPath);
      const parentName = parentInfo.remoteUrl
        ? getRepoName(parentInfo.remoteUrl)
        : repoInfo.parentPath.split("/").pop() || "unknown";

      const parentRepo = await api.registerRepository({
        name: parentName,
        localPath: repoInfo.parentPath,
        remoteUrl: parentInfo.remoteUrl,
        defaultBranch: parentInfo.defaultBranch,
        isWorktree: false,
      });

      parentRepositoryId = parentRepo.id;
      spinner.text = "Registering worktree...";
    }

    // Register the repository
    const name = repoInfo.remoteUrl
      ? getRepoName(repoInfo.remoteUrl)
      : cwd.split("/").pop() || "unknown";

    const repo = await api.registerRepository({
      name,
      localPath: cwd,
      remoteUrl: repoInfo.remoteUrl,
      defaultBranch: repoInfo.defaultBranch,
      isWorktree: repoInfo.isWorktree,
      worktreeBranch: repoInfo.worktreeBranch,
      parentRepositoryId,
    });

    spinner.succeed("Repository registered!");

    console.log(`\n${chalk.bold("Repository Details:")}`);
    console.log(`  Name: ${chalk.cyan(repo.name)}`);
    console.log(`  Path: ${chalk.gray(repo.localPath)}`);
    if (repo.remoteUrl) {
      console.log(`  Remote: ${chalk.gray(repo.remoteUrl)}`);
    }
    if (repo.isWorktree) {
      console.log(`  Worktree: ${chalk.green("Yes")} (${repo.worktreeBranch})`);
    }
    console.log();
  } catch (error) {
    spinner.fail("Registration failed");
    logger.error(`Register error: ${error}`);
    console.log(chalk.red(`\nError: ${(error as Error).message}`));
    process.exit(1);
  }
}

/**
 * Unregister command - remove current directory from registered projects
 */
export async function unregisterCommand(): Promise<void> {
  // Check if linked
  const isLinked = await credentials.isLinked();
  if (!isLinked) {
    console.log(chalk.yellow("Device not linked. Run 'unbound link' first."));
    process.exit(1);
  }

  const cwd = process.cwd();
  const spinner = ora("Finding repository...").start();

  try {
    // Get credentials
    const apiKey = await credentials.getApiKey();
    const deviceId = await credentials.getDeviceId();

    if (!(apiKey && deviceId)) {
      spinner.fail("Missing credentials");
      process.exit(1);
    }

    const api = new ApiClient(apiKey, deviceId);

    // List repositories to find current one
    const repos = await api.listRepositories();
    const currentRepo = repos.find((r) => r.localPath === cwd);

    if (!currentRepo) {
      spinner.fail("Repository not registered");
      console.log(
        chalk.yellow("\nThis directory is not registered as a project.")
      );
      process.exit(1);
    }

    spinner.text = "Archiving repository...";

    await api.archiveRepository(currentRepo.id);

    spinner.succeed("Repository unregistered!");
    console.log(`\nRemoved: ${chalk.cyan(currentRepo.name)}`);
  } catch (error) {
    spinner.fail("Unregistration failed");
    logger.error(`Unregister error: ${error}`);
    console.log(chalk.red(`\nError: ${(error as Error).message}`));
    process.exit(1);
  }
}

/**
 * List command - show all registered projects
 */
export async function listCommand(): Promise<void> {
  // Check if linked
  const isLinked = await credentials.isLinked();
  if (!isLinked) {
    console.log(chalk.yellow("Device not linked. Run 'unbound link' first."));
    process.exit(1);
  }

  const spinner = ora("Loading repositories...").start();

  try {
    // Get credentials
    const apiKey = await credentials.getApiKey();
    const deviceId = await credentials.getDeviceId();

    if (!(apiKey && deviceId)) {
      spinner.fail("Missing credentials");
      process.exit(1);
    }

    const api = new ApiClient(apiKey, deviceId);
    const repos = await api.listRepositories();

    spinner.stop();

    if (repos.length === 0) {
      console.log(chalk.yellow("\nNo repositories registered."));
      console.log("Run 'unbound register' in a git repository to add one.\n");
      return;
    }

    console.log(chalk.bold("\nRegistered Repositories:\n"));

    for (const repo of repos) {
      const status =
        repo.status === "active"
          ? chalk.green("active")
          : chalk.gray("archived");

      console.log(`  ${chalk.cyan(repo.name)} [${status}]`);
      console.log(`    Path: ${chalk.gray(repo.localPath)}`);
      if (repo.isWorktree) {
        console.log(`    Worktree: ${chalk.blue(repo.worktreeBranch)}`);
      }
      console.log();
    }
  } catch (error) {
    spinner.fail("Failed to list repositories");
    logger.error(`List error: ${error}`);
    console.log(chalk.red(`\nError: ${(error as Error).message}`));
    process.exit(1);
  }
}
