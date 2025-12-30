import { exec } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { promisify } from "node:util";
import { deviceInfo, paths } from "../config.js";
import { logger } from "./logger.js";

const execAsync = promisify(exec);

/**
 * Generate macOS launchd plist content
 */
function generateLaunchdPlist(): string {
  // Use which to find the unbound binary, fallback to npx
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.unbound.daemon</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>unbound start</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>${paths.logsDir}/daemon.out.log</string>
  <key>StandardErrorPath</key>
  <string>${paths.logsDir}/daemon.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:$HOME/.local/bin</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>${paths.configDir}</string>
</dict>
</plist>`;
}

/**
 * Generate Linux systemd service content
 */
function generateSystemdService(): string {
  return `[Unit]
Description=Unbound CLI Daemon
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'unbound start'
Restart=on-failure
RestartSec=5
StandardOutput=append:${paths.logsDir}/daemon.out.log
StandardError=append:${paths.logsDir}/daemon.err.log
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin

[Install]
WantedBy=default.target
`;
}

/**
 * Install daemon service for the current platform
 */
export async function installDaemonService(): Promise<void> {
  if (deviceInfo.isMac) {
    await installLaunchdService();
  } else if (deviceInfo.isLinux) {
    await installSystemdService();
  } else {
    logger.warn("Daemon auto-start not supported on this platform");
  }
}

/**
 * Install macOS launchd service
 */
async function installLaunchdService(): Promise<void> {
  const plistContent = generateLaunchdPlist();

  // Ensure LaunchAgents directory exists
  await mkdir(dirname(paths.launchdPlist), { recursive: true });

  // Ensure logs directory exists
  await mkdir(paths.logsDir, { recursive: true });

  // Unload existing service if present
  try {
    await execAsync(`launchctl unload ${paths.launchdPlist}`);
  } catch {
    // Ignore if not loaded
  }

  // Write plist file
  await writeFile(paths.launchdPlist, plistContent);

  // Load the service
  await execAsync(`launchctl load ${paths.launchdPlist}`);

  logger.info("launchd service installed and started");
}

/**
 * Install Linux systemd service
 */
async function installSystemdService(): Promise<void> {
  const serviceContent = generateSystemdService();

  // Ensure systemd user directory exists
  await mkdir(dirname(paths.systemdService), { recursive: true });

  // Ensure logs directory exists
  await mkdir(paths.logsDir, { recursive: true });

  // Write service file
  await writeFile(paths.systemdService, serviceContent);

  // Reload systemd
  await execAsync("systemctl --user daemon-reload");

  // Enable and start service
  await execAsync("systemctl --user enable unbound");
  await execAsync("systemctl --user start unbound");

  logger.info("systemd service installed and started");
}

/**
 * Check if daemon service is running
 */
export async function isDaemonRunning(): Promise<boolean> {
  if (deviceInfo.isMac) {
    try {
      const { stdout } = await execAsync(
        "launchctl list | grep com.unbound.daemon"
      );
      return stdout.includes("com.unbound.daemon");
    } catch {
      return false;
    }
  }

  if (deviceInfo.isLinux) {
    try {
      const { stdout } = await execAsync(
        "systemctl --user is-active unbound 2>/dev/null"
      );
      return stdout.trim() === "active";
    } catch {
      return false;
    }
  }

  // Check PID file as fallback
  try {
    const { readFile } = await import("node:fs/promises");
    const pidStr = await readFile(paths.pidFile, "utf-8");
    const pid = Number.parseInt(pidStr.trim(), 10);
    process.kill(pid, 0); // Signal 0 just checks if process exists
    return true;
  } catch {
    return false;
  }
}

/**
 * Get daemon service status
 */
export async function getDaemonStatus(): Promise<{
  running: boolean;
  pid?: number;
  uptime?: string;
}> {
  const running = await isDaemonRunning();

  if (!running) {
    return { running: false };
  }

  try {
    const { readFile } = await import("node:fs/promises");
    const pidStr = await readFile(paths.pidFile, "utf-8");
    const pid = Number.parseInt(pidStr.trim(), 10);

    return { running: true, pid };
  } catch {
    return { running: true };
  }
}
