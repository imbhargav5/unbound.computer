import { unlink } from "node:fs/promises";
import chalk from "chalk";
import ora from "ora";
import { credentials } from "../auth/index.js";
import { deviceInfo, paths } from "../config.js";
import { logger } from "../utils/index.js";

/**
 * Unlink command - remove device registration
 */
export async function unlinkCommand(): Promise<void> {
  console.log(chalk.bold("\nUnbound CLI Unlink\n"));

  await credentials.init();
  const isLinked = await credentials.isLinked();

  if (!isLinked) {
    console.log(chalk.yellow("Device is not linked."));
    return;
  }

  const spinner = ora("Unlinking device...").start();

  try {
    // Stop daemon if running
    spinner.text = "Stopping daemon...";
    await stopDaemon();

    // Clear credentials
    spinner.text = "Clearing credentials...";
    await credentials.clear();

    // Remove daemon service files
    spinner.text = "Removing daemon service...";
    await removeDaemonService();

    spinner.succeed("Device unlinked successfully!");

    console.log(
      `\nDevice ${chalk.cyan(deviceInfo.hostname)} has been unlinked.`
    );
    console.log("All local credentials have been removed.\n");
  } catch (error) {
    spinner.fail("Unlink failed");
    logger.error(`Unlink error: ${error}`);
    console.log(chalk.red(`\nError: ${(error as Error).message}`));
    process.exit(1);
  }
}

/**
 * Stop the daemon process
 */
async function stopDaemon(): Promise<void> {
  try {
    const { readFile } = await import("node:fs/promises");
    const pidStr = await readFile(paths.pidFile, "utf-8");
    const pid = Number.parseInt(pidStr.trim(), 10);

    if (pid) {
      try {
        process.kill(pid, "SIGTERM");
        // Wait a bit for graceful shutdown
        await new Promise((resolve) => setTimeout(resolve, 1000));
      } catch {
        // Process might not exist
      }
    }

    // Remove PID file
    await unlink(paths.pidFile).catch(() => {});
  } catch {
    // PID file might not exist
  }
}

/**
 * Remove daemon service files
 */
async function removeDaemonService(): Promise<void> {
  if (deviceInfo.isMac) {
    // Unload and remove launchd plist
    try {
      const { exec } = await import("node:child_process");
      const { promisify } = await import("node:util");
      const execAsync = promisify(exec);

      await execAsync(`launchctl unload ${paths.launchdPlist}`).catch(() => {});
      await unlink(paths.launchdPlist).catch(() => {});
    } catch {
      // Service might not be installed
    }
  } else if (deviceInfo.isLinux) {
    // Stop and remove systemd service
    try {
      const { exec } = await import("node:child_process");
      const { promisify } = await import("node:util");
      const execAsync = promisify(exec);

      await execAsync("systemctl --user stop unbound").catch(() => {});
      await execAsync("systemctl --user disable unbound").catch(() => {});
      await unlink(paths.systemdService).catch(() => {});
      await execAsync("systemctl --user daemon-reload").catch(() => {});
    } catch {
      // Service might not be installed
    }
  }
}
