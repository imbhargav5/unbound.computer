import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import { type ClaudeProcess, createClaudeProcess } from "./process.js";
import { createMessageQueue, type MessageQueue } from "./queue.js";
import {
  type MessageType,
  type SessionConfig,
  type SessionMetadata,
  type SessionResult,
  SessionState,
  STATE_TRANSITIONS,
  type StateChangeData,
} from "./types.js";

/**
 * Session events interface
 */
export interface SessionEvents {
  error: [error: Error];
  exit: [code: number | null, signal: string | null];
  message: [message: { type: MessageType; content: string }];
  output: [content: string];
  stateChange: [data: StateChangeData];
}

/**
 * Claude Code session
 * Manages the lifecycle of a single Claude Code process
 */
export class Session extends EventEmitter {
  private config: SessionConfig;
  private state: SessionState = SessionState.INITIALIZING;
  private process: ClaudeProcess | null = null;
  private queue: MessageQueue;
  private metadata: SessionMetadata;
  private outputBuffer = "";
  private claudeCommand: string;
  private claudeArgs: string[];

  constructor(
    config: SessionConfig,
    claudeCommand = "claude",
    claudeArgs: string[] = ["--dangerously-skip-permissions"]
  ) {
    super();
    this.config = config;
    this.claudeCommand = claudeCommand;
    this.claudeArgs = claudeArgs;
    this.queue = createMessageQueue(config.sessionId);

    this.metadata = {
      sessionId: config.sessionId,
      state: this.state,
      repositoryUrl: undefined,
      worktreePath: config.worktreePath,
      branch: config.branch,
      deviceId: config.deviceId,
      userId: config.userId,
      startedAt: new Date(),
      lastActivityAt: new Date(),
      messageCount: 0,
    };

    // Set up queue event handlers
    this.setupQueueHandlers();
  }

  /**
   * Get session ID
   */
  getId(): string {
    return this.config.sessionId;
  }

  /**
   * Get current state
   */
  getState(): SessionState {
    return this.state;
  }

  /**
   * Get session metadata
   */
  getMetadata(): SessionMetadata {
    return {
      ...this.metadata,
      state: this.state,
      lastActivityAt: new Date(),
      durationMs: Date.now() - this.metadata.startedAt.getTime(),
    };
  }

  /**
   * Get message queue
   */
  getQueue(): MessageQueue {
    return this.queue;
  }

  /**
   * Start the session
   */
  async start(): Promise<SessionResult<void>> {
    if (this.state !== SessionState.INITIALIZING) {
      return {
        success: false,
        error: `Cannot start session in state: ${this.state}`,
      };
    }

    try {
      // Create the Claude process
      const cwd = this.config.worktreePath || this.config.repositoryPath;

      this.process = createClaudeProcess(this.claudeCommand, this.claudeArgs, {
        cwd,
        env: this.config.env,
        timeoutMs: this.config.timeoutMs,
      });

      // Set up process event handlers
      this.setupProcessHandlers();

      // Spawn the process
      this.process.spawn();

      // Transition to running state
      this.transitionTo(SessionState.RUNNING);

      return { success: true };
    } catch (error) {
      this.transitionTo(SessionState.ERROR);
      this.metadata.error =
        error instanceof Error ? error.message : String(error);
      return {
        success: false,
        error: this.metadata.error,
      };
    }
  }

  /**
   * Send input to the session
   */
  sendInput(content: string): SessionResult<void> {
    if (this.state !== SessionState.RUNNING) {
      return {
        success: false,
        error: `Cannot send input in state: ${this.state}`,
      };
    }

    if (!this.process?.isRunning()) {
      return {
        success: false,
        error: "Process is not running",
      };
    }

    // Enqueue the message
    const message = this.queue.enqueue("input", content);
    this.metadata.messageCount++;
    this.metadata.lastActivityAt = new Date();

    // Write to process stdin
    const written = this.process.writeLine(content);
    if (!written) {
      this.queue.scheduleRetry(message.id);
      return {
        success: false,
        error: "Failed to write to process",
      };
    }

    return { success: true };
  }

  /**
   * Pause the session
   */
  pause(): SessionResult<void> {
    if (this.state !== SessionState.RUNNING) {
      return {
        success: false,
        error: `Cannot pause session in state: ${this.state}`,
      };
    }

    // Send SIGSTOP to pause the process
    this.process?.kill("SIGSTOP");
    this.transitionTo(SessionState.PAUSED);

    return { success: true };
  }

  /**
   * Resume the session
   */
  resume(): SessionResult<void> {
    if (this.state !== SessionState.PAUSED) {
      return {
        success: false,
        error: `Cannot resume session in state: ${this.state}`,
      };
    }

    // Send SIGCONT to resume the process
    this.process?.kill("SIGCONT");
    this.transitionTo(SessionState.RUNNING);

    return { success: true };
  }

  /**
   * Stop the session
   */
  async stop(): Promise<SessionResult<void>> {
    if (
      this.state === SessionState.COMPLETED ||
      this.state === SessionState.ERROR
    ) {
      return { success: true };
    }

    try {
      await this.process?.shutdown();
      this.transitionTo(SessionState.COMPLETED);
      this.metadata.endedAt = new Date();
      this.metadata.durationMs =
        this.metadata.endedAt.getTime() - this.metadata.startedAt.getTime();

      return { success: true };
    } catch (error) {
      this.transitionTo(SessionState.ERROR);
      this.metadata.error =
        error instanceof Error ? error.message : String(error);
      return {
        success: false,
        error: this.metadata.error,
      };
    }
  }

  /**
   * Force kill the session
   */
  kill(): void {
    this.process?.kill("SIGKILL");
    this.transitionTo(SessionState.ERROR);
    this.metadata.error = "Session killed";
    this.metadata.endedAt = new Date();
  }

  /**
   * Check if session is active (running or paused)
   */
  isActive(): boolean {
    return (
      this.state === SessionState.RUNNING || this.state === SessionState.PAUSED
    );
  }

  /**
   * Check if session is terminal (completed or error)
   */
  isTerminal(): boolean {
    return (
      this.state === SessionState.COMPLETED || this.state === SessionState.ERROR
    );
  }

  /**
   * Get process info
   */
  getProcessInfo() {
    return this.process?.getInfo() ?? null;
  }

  /**
   * Transition to a new state
   */
  private transitionTo(newState: SessionState): boolean {
    const validTransitions = STATE_TRANSITIONS[this.state];
    if (!validTransitions.includes(newState)) {
      return false;
    }

    const previousState = this.state;
    this.state = newState;
    this.metadata.state = newState;

    this.emit("stateChange", {
      previousState,
      newState,
    });

    return true;
  }

  /**
   * Set up process event handlers
   */
  private setupProcessHandlers(): void {
    if (!this.process) return;

    this.process.on("stdout", (chunk) => {
      const text = chunk.data.toString();
      this.outputBuffer += text;

      // Emit output
      this.emit("output", text);

      // Enqueue output message
      this.queue.enqueue("output", text);
      this.metadata.messageCount++;
      this.metadata.lastActivityAt = new Date();
    });

    this.process.on("stderr", (chunk) => {
      const text = chunk.data.toString();

      // Emit as error
      this.emit("error", new Error(text));

      // Enqueue error message
      this.queue.enqueue("error", text);
    });

    this.process.on("exit", (code, signal) => {
      if (code === 0) {
        this.transitionTo(SessionState.COMPLETED);
      } else {
        this.transitionTo(SessionState.ERROR);
        this.metadata.error = signal
          ? `Process killed with signal ${signal}`
          : `Process exited with code ${code}`;
      }

      this.metadata.endedAt = new Date();
      this.metadata.durationMs =
        this.metadata.endedAt.getTime() - this.metadata.startedAt.getTime();

      this.emit("exit", code, signal);
    });

    this.process.on("error", (error) => {
      this.transitionTo(SessionState.ERROR);
      this.metadata.error = error.message;
      this.emit("error", error);
    });
  }

  /**
   * Set up queue event handlers
   */
  private setupQueueHandlers(): void {
    this.queue.on("retry", (message) => {
      if (message.type === "input" && this.process?.isRunning()) {
        this.process.writeLine(message.content);
      }
    });
  }

  /**
   * Clean up resources
   */
  cleanup(): void {
    this.queue.clear();
    this.removeAllListeners();
  }

  // Type-safe event methods
  override on(
    event: "stateChange",
    listener: (data: StateChangeData) => void
  ): this;
  override on(event: "output", listener: (content: string) => void): this;
  override on(event: "error", listener: (error: Error) => void): this;
  override on(
    event: "exit",
    listener: (code: number | null, signal: string | null) => void
  ): this;
  // biome-ignore lint/suspicious/noExplicitAny: Required for EventEmitter overload compatibility
  override on(event: string, listener: (...args: any[]) => void): this {
    return super.on(event, listener);
  }
}

/**
 * Create a new session
 */
export function createSession(
  config: SessionConfig,
  claudeCommand?: string,
  claudeArgs?: string[]
): Session {
  return new Session(config, claudeCommand, claudeArgs);
}

/**
 * Create a session with a generated ID
 */
export function createSessionWithId(
  config: Omit<SessionConfig, "sessionId">,
  claudeCommand?: string,
  claudeArgs?: string[]
): Session {
  return new Session(
    { ...config, sessionId: randomUUID() },
    claudeCommand,
    claudeArgs
  );
}
