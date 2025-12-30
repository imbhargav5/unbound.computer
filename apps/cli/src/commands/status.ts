import { readFile } from "node:fs/promises";
import chalk from "chalk";
import { credentials } from "../auth/index.js";
import { ApiClient } from "../client/index.js";
import { deviceInfo, paths } from "../config.js";

/**
 * Status command - show daemon status and connection info
 */
export async function statusCommand(): Promise<void> {
  console.log(chalk.bold("\nUnbound CLI Status\n"));

  // Device info
  console.log(chalk.blue("Device:"));
  console.log(`  Hostname: ${chalk.cyan(deviceInfo.hostname)}`);
  console.log(`  Platform: ${chalk.cyan(deviceInfo.platform)}`);
  console.log();

  // Link status
  console.log(chalk.blue("Link Status:"));
  await credentials.init();
  const isLinked = await credentials.isLinked();

  if (!isLinked) {
    console.log(`  Status: ${chalk.yellow("Not linked")}`);
    console.log("  Run 'unbound link' to connect to your account.\n");
    return;
  }

  const deviceId = await credentials.getDeviceId();
  const linkedAt = credentials.getLinkedAt();
  const userId = credentials.getUserId();

  console.log(`  Status: ${chalk.green("Linked")}`);
  console.log(`  User ID: ${chalk.cyan(userId || "unknown")}`);
  console.log(`  Device ID: ${chalk.gray(deviceId || "unknown")}`);
  if (linkedAt) {
    console.log(`  Linked: ${chalk.gray(linkedAt.toLocaleString())}`);
  }
  console.log();

  // Daemon status
  console.log(chalk.blue("Daemon:"));
  try {
    const pidStr = await readFile(paths.pidFile, "utf-8");
    const pid = Number.parseInt(pidStr.trim(), 10);

    // Check if process is running
    try {
      process.kill(pid, 0); // Signal 0 just checks if process exists
      console.log(`  Status: ${chalk.green("Running")}`);
      console.log(`  PID: ${chalk.cyan(pid)}`);
    } catch {
      console.log(`  Status: ${chalk.yellow("Not running")} (stale PID file)`);
    }
  } catch {
    console.log(`  Status: ${chalk.yellow("Not running")}`);
  }
  console.log();

  // Active sessions
  console.log(chalk.blue("Active Sessions:"));
  try {
    const apiKey = await credentials.getApiKey();
    if (apiKey && deviceId) {
      const api = new ApiClient(apiKey, deviceId);
      const sessions = await api.listSessions("active");

      if (sessions.length === 0) {
        console.log(`  ${chalk.gray("No active sessions")}`);
      } else {
        for (const session of sessions) {
          console.log(`  - ${chalk.cyan(session.id.slice(0, 8))}`);
          console.log(`    Repository: ${session.repositoryId.slice(0, 8)}`);
          if (session.currentBranch) {
            console.log(`    Branch: ${session.currentBranch}`);
          }
          console.log(
            `    Started: ${new Date(session.sessionStartedAt).toLocaleString()}`
          );
        }
      }
    } else {
      console.log(`  ${chalk.gray("Unable to fetch sessions")}`);
    }
  } catch (error) {
    console.log(`  ${chalk.gray("Unable to fetch sessions")}`);
  }
  console.log();
}
