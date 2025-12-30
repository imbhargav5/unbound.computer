import { appendFile, writeFile } from "node:fs/promises";
import { parseSessionCommand, type SessionCommand } from "@unbound/protocol";
import { credentials } from "./auth/index.js";
import { ApiClient, RelayClient } from "./client/index.js";
import { paths } from "./config.js";
import { ensureDir, logger } from "./utils/index.js";

/**
 * Active session state
 */
interface ActiveSession {
  id: string;
  repositoryId: string;
  sessionPid?: number;
}

/**
 * Daemon state
 */
class Daemon {
  private relayClient: RelayClient | null = null;
  private apiClient: ApiClient | null = null;
  private activeSessions: Map<string, ActiveSession> = new Map();
  private isShuttingDown = false;

  /**
   * Start the daemon
   */
  async start(): Promise<void> {
    logger.info("Starting Unbound daemon...");

    // Initialize credentials
    await credentials.init();

    // Check if linked
    const isLinked = await credentials.isLinked();
    if (!isLinked) {
      logger.error("Device not linked. Run 'unbound link' first.");
      process.exit(1);
    }

    // Get credentials
    const apiKey = await credentials.getApiKey();
    const deviceId = await credentials.getDeviceId();

    if (!(apiKey && deviceId)) {
      logger.error("Missing credentials");
      process.exit(1);
    }

    // Ensure logs directory exists
    await ensureDir(paths.logsDir);

    // Write PID file
    await writeFile(paths.pidFile, String(process.pid));

    // Create API client
    this.apiClient = new ApiClient(apiKey, deviceId);

    // Create relay client
    this.relayClient = new RelayClient(apiKey, deviceId);

    // Set up relay event handlers
    this.setupRelayHandlers();

    // Connect to relay
    this.relayClient.connect();

    // Set up signal handlers for graceful shutdown
    this.setupSignalHandlers();

    logger.info("Daemon started successfully");
    await this.log("Daemon started");
  }

  /**
   * Set up relay event handlers
   */
  private setupRelayHandlers(): void {
    if (!this.relayClient) return;

    this.relayClient.on("connected", () => {
      logger.info("Connected to relay server");
      this.log("Connected to relay server");
    });

    this.relayClient.on("authenticated", () => {
      logger.info("Authenticated with relay");
      this.log("Authenticated with relay");
    });

    this.relayClient.on("authFailed", (error) => {
      logger.error(`Authentication failed: ${error}`);
      this.log(`Authentication failed: ${error}`);
    });

    this.relayClient.on("disconnected", (code, reason) => {
      logger.warn(`Disconnected from relay: ${code} ${reason}`);
      this.log(`Disconnected from relay: ${code} ${reason}`);
    });

    this.relayClient.on("message", async (envelope) => {
      // Handle incoming messages
      if (envelope.type === "session") {
        await this.handleSessionMessage(envelope.sessionId, envelope.payload);
      }
    });

    this.relayClient.on("error", (error) => {
      logger.error(`Relay error: ${error.message}`);
      this.log(`Relay error: ${error.message}`);
    });
  }

  /**
   * Handle session command messages
   */
  private async handleSessionMessage(
    sessionId: string,
    payload: string
  ): Promise<void> {
    try {
      // Decode and parse the session command
      // Note: In a real implementation, this would be decrypted first
      const decoded = Buffer.from(payload, "base64").toString("utf-8");
      const result = parseSessionCommand(JSON.parse(decoded));

      if (!result.success) {
        logger.warn(`Invalid session command: ${result.error}`);
        return;
      }

      const command = result.data;
      await this.executeSessionCommand(sessionId, command);
    } catch (error) {
      logger.error(`Error handling session message: ${error}`);
    }
  }

  /**
   * Execute a session command
   */
  private async executeSessionCommand(
    sessionId: string,
    command: SessionCommand
  ): Promise<void> {
    logger.info(`Executing session command: ${command.command}`);
    await this.log(`Session command: ${command.command}`);

    switch (command.command) {
      case "START_SESSION": {
        // Start a new Claude Code session
        const { repositoryId, branch } = command;
        await this.startSession(sessionId, repositoryId, branch);
        break;
      }

      case "END_SESSION": {
        // End the current session
        await this.endSession(sessionId);
        break;
      }

      case "PAUSE_SESSION": {
        // Pause the current session
        await this.pauseSession(sessionId);
        break;
      }

      case "RESUME_SESSION": {
        // Resume a paused session
        await this.resumeSession(sessionId);
        break;
      }

      case "INPUT": {
        // Handle user input
        const { content, inputType } = command;
        await this.handleInput(sessionId, content, inputType);
        break;
      }

      default:
        logger.warn(`Unknown session command: ${command}`);
    }
  }

  /**
   * Start a new session
   */
  private async startSession(
    sessionId: string,
    repositoryId: string,
    _branch?: string
  ): Promise<void> {
    logger.info(`Starting session ${sessionId} for repo ${repositoryId}`);

    // TODO: Start Claude Code process
    // For now, just track the session

    const session: ActiveSession = {
      id: sessionId,
      repositoryId,
    };

    this.activeSessions.set(sessionId, session);

    // Subscribe to session on relay
    this.relayClient?.subscribe(sessionId);

    await this.log(`Started session ${sessionId}`);
  }

  /**
   * End a session
   */
  private async endSession(sessionId: string): Promise<void> {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      logger.warn(`Session ${sessionId} not found`);
      return;
    }

    logger.info(`Ending session ${sessionId}`);

    // TODO: Stop Claude Code process if running

    // Unsubscribe from relay
    this.relayClient?.unsubscribe(sessionId);

    // Remove from active sessions
    this.activeSessions.delete(sessionId);

    await this.log(`Ended session ${sessionId}`);
  }

  /**
   * Pause a session
   */
  private async pauseSession(sessionId: string): Promise<void> {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      logger.warn(`Session ${sessionId} not found`);
      return;
    }

    logger.info(`Pausing session ${sessionId}`);
    // TODO: Pause Claude Code process

    await this.log(`Paused session ${sessionId}`);
  }

  /**
   * Resume a session
   */
  private async resumeSession(sessionId: string): Promise<void> {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      logger.warn(`Session ${sessionId} not found`);
      return;
    }

    logger.info(`Resuming session ${sessionId}`);
    // TODO: Resume Claude Code process

    await this.log(`Resumed session ${sessionId}`);
  }

  /**
   * Handle user input
   */
  private async handleInput(
    sessionId: string,
    content: string,
    inputType: string
  ): Promise<void> {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      logger.warn(`Session ${sessionId} not found`);
      return;
    }

    logger.debug(`Input for session ${sessionId}: ${inputType}`);
    // TODO: Send input to Claude Code process
  }

  /**
   * Set up signal handlers for graceful shutdown
   */
  private setupSignalHandlers(): void {
    const shutdown = async (signal: string) => {
      if (this.isShuttingDown) return;
      this.isShuttingDown = true;

      logger.info(`Received ${signal}, shutting down...`);
      await this.log(`Received ${signal}, shutting down...`);

      // End all active sessions
      for (const sessionId of this.activeSessions.keys()) {
        await this.endSession(sessionId);
      }

      // Disconnect from relay
      this.relayClient?.disconnect();

      // Remove PID file
      try {
        const { unlink } = await import("node:fs/promises");
        await unlink(paths.pidFile);
      } catch {
        // Ignore errors
      }

      logger.info("Daemon stopped");
      await this.log("Daemon stopped");

      process.exit(0);
    };

    process.on("SIGTERM", () => shutdown("SIGTERM"));
    process.on("SIGINT", () => shutdown("SIGINT"));
  }

  /**
   * Append to log file
   */
  private async log(message: string): Promise<void> {
    const timestamp = new Date().toISOString();
    const line = `${timestamp} ${message}\n`;
    await appendFile(paths.daemonLog, line).catch(() => {});
  }
}

/**
 * Start the daemon
 */
export async function startDaemon(): Promise<void> {
  const daemon = new Daemon();
  await daemon.start();

  // Keep the process running
  await new Promise(() => {});
}

// Run if this is the main module
if (import.meta.url === `file://${process.argv[1]}`) {
  startDaemon().catch((error) => {
    console.error("Daemon error:", error);
    process.exit(1);
  });
}
