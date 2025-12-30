import { homedir, hostname, platform, type } from "node:os";
import { join } from "node:path";
import { z } from "zod";

/**
 * CLI configuration schema
 */
const ConfigSchema = z.object({
  // API endpoints
  apiUrl: z.string().url().default("https://app.unbound.computer"),
  relayUrl: z.string().url().default("wss://relay.unbound.computer"),

  // Logging
  logLevel: z.enum(["debug", "info", "warn", "error"]).default("info"),

  // Timeouts (milliseconds)
  apiTimeout: z.number().default(30_000),
  wsReconnectDelay: z.number().default(1000),
  wsMaxReconnectDelay: z.number().default(30_000),
  heartbeatInterval: z.number().default(30_000),

  // OAuth
  oauthCallbackPort: z.number().default(9876),
  oauthTimeout: z.number().default(300_000), // 5 minutes
});

export type Config = z.infer<typeof ConfigSchema>;

/**
 * Load configuration from environment
 */
function loadConfig(): Config {
  return ConfigSchema.parse({
    apiUrl: process.env.UNBOUND_API_URL,
    relayUrl: process.env.UNBOUND_RELAY_URL,
    logLevel: process.env.UNBOUND_LOG_LEVEL,
  });
}

export const config = loadConfig();

/**
 * Paths and directories
 */
export const paths = {
  // Config directory
  configDir: join(homedir(), ".unbound"),
  configFile: join(homedir(), ".unbound", "config.json"),
  logsDir: join(homedir(), ".unbound", "logs"),
  daemonLog: join(homedir(), ".unbound", "logs", "daemon.log"),
  pidFile: join(homedir(), ".unbound", "daemon.pid"),

  // macOS launchd
  launchdPlist: join(
    homedir(),
    "Library",
    "LaunchAgents",
    "com.unbound.daemon.plist"
  ),

  // Linux systemd
  systemdService: join(
    homedir(),
    ".config",
    "systemd",
    "user",
    "unbound.service"
  ),
} as const;

/**
 * Device information
 */
export const deviceInfo = {
  hostname: hostname(),
  platform: platform(),
  type: type(),
  isLinux: platform() === "linux",
  isMac: platform() === "darwin",
  isWindows: platform() === "win32",
} as const;

/**
 * Service name for OS keychain
 */
export const KEYCHAIN_SERVICE = "com.unbound.cli";

/**
 * API endpoints
 */
export const endpoints = {
  generateToken: "/api/v1/cli/generate-token",
  repositories: "/api/v1/cli/repositories",
  sessions: "/api/v1/cli/sessions",
} as const;
