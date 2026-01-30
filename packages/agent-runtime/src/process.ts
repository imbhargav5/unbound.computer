import { type ChildProcess, spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import type { ProcessInfo, SpawnOptions, StreamChunk } from "./types.js";

/**
 * Process events interface for documentation
 */
export interface ProcessEvents {
  stdout: [chunk: StreamChunk];
  stderr: [chunk: StreamChunk];
  exit: [code: number | null, signal: string | null];
  error: [error: Error];
  spawn: [];
}

/**
 * Claude Code process wrapper
 */
export class ClaudeProcess extends EventEmitter {
  private process: ChildProcess | null = null;
  private processInfo: ProcessInfo | null = null;
  private command: string;
  private args: string[];
  private options: SpawnOptions;
  private timeoutId: NodeJS.Timeout | null = null;

  constructor(command: string, args: string[], options: SpawnOptions) {
    super();
    this.command = command;
    this.args = args;
    this.options = options;
  }

  /**
   * Spawn the Claude Code process
   */
  spawn(): void {
    if (this.process) {
      throw new Error("Process already spawned");
    }

    const env = {
      ...process.env,
      ...this.options.env,
      // Force non-interactive mode
      FORCE_COLOR: "1",
      TERM: "xterm-256color",
    };

    this.process = spawn(this.command, this.args, {
      cwd: this.options.cwd,
      env,
      stdio: ["pipe", "pipe", "pipe"],
      detached: false,
    });

    this.processInfo = {
      pid: this.process.pid!,
      running: true,
      startedAt: new Date(),
    };

    // Set up timeout if configured
    if (this.options.timeoutMs) {
      this.timeoutId = setTimeout(() => {
        this.kill("SIGTERM");
      }, this.options.timeoutMs);
    }

    // Handle stdout
    this.process.stdout?.on("data", (data: Buffer) => {
      this.emit("stdout", {
        type: "stdout",
        data,
        timestamp: new Date(),
      } satisfies StreamChunk);
    });

    // Handle stderr
    this.process.stderr?.on("data", (data: Buffer) => {
      this.emit("stderr", {
        type: "stderr",
        data,
        timestamp: new Date(),
      } satisfies StreamChunk);
    });

    // Handle process exit
    this.process.on("exit", (code, signal) => {
      this.clearTimeout();
      if (this.processInfo) {
        this.processInfo.running = false;
        this.processInfo.exitCode = code ?? undefined;
        this.processInfo.signal = signal ?? undefined;
        this.processInfo.endedAt = new Date();
      }
      this.emit("exit", code, signal);
    });

    // Handle process error
    this.process.on("error", (error) => {
      this.clearTimeout();
      if (this.processInfo) {
        this.processInfo.running = false;
        this.processInfo.endedAt = new Date();
      }
      this.emit("error", error);
    });

    // Handle spawn success
    this.process.on("spawn", () => {
      this.emit("spawn");
    });
  }

  /**
   * Write to stdin
   */
  write(data: string | Buffer): boolean {
    if (!this.process?.stdin?.writable) {
      return false;
    }
    return this.process.stdin.write(data);
  }

  /**
   * Write line to stdin (with newline)
   */
  writeLine(data: string): boolean {
    return this.write(`${data}\n`);
  }

  /**
   * Close stdin
   */
  closeStdin(): void {
    this.process?.stdin?.end();
  }

  /**
   * Send signal to process
   */
  kill(signal: NodeJS.Signals = "SIGTERM"): boolean {
    this.clearTimeout();
    if (!(this.process && this.processInfo?.running)) {
      return false;
    }
    return this.process.kill(signal);
  }

  /**
   * Gracefully shutdown the process
   */
  async shutdown(timeoutMs = 5000): Promise<void> {
    if (!(this.process && this.processInfo?.running)) {
      return;
    }

    // Try graceful shutdown first
    this.kill("SIGTERM");

    // Wait for exit or timeout
    await Promise.race([
      new Promise<void>((resolve) => {
        this.once("exit", () => resolve());
      }),
      new Promise<void>((resolve) => {
        setTimeout(() => {
          // Force kill if still running
          if (this.processInfo?.running) {
            this.kill("SIGKILL");
          }
          resolve();
        }, timeoutMs);
      }),
    ]);
  }

  /**
   * Get process info
   */
  getInfo(): ProcessInfo | null {
    return this.processInfo ? { ...this.processInfo } : null;
  }

  /**
   * Check if process is running
   */
  isRunning(): boolean {
    return this.processInfo?.running ?? false;
  }

  /**
   * Get process ID
   */
  getPid(): number | undefined {
    return this.processInfo?.pid;
  }

  /**
   * Clear timeout
   */
  private clearTimeout(): void {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId);
      this.timeoutId = null;
    }
  }

  // Type-safe event methods
  override on(event: "stdout", listener: (chunk: StreamChunk) => void): this;
  override on(event: "stderr", listener: (chunk: StreamChunk) => void): this;
  override on(
    event: "exit",
    listener: (code: number | null, signal: string | null) => void
  ): this;
  override on(event: "error", listener: (error: Error) => void): this;
  override on(event: "spawn", listener: () => void): this;
  // biome-ignore lint/suspicious/noExplicitAny: Required for EventEmitter overload compatibility
  override on(event: string, listener: (...args: any[]) => void): this {
    return super.on(event, listener);
  }

  override once(event: "stdout", listener: (chunk: StreamChunk) => void): this;
  override once(event: "stderr", listener: (chunk: StreamChunk) => void): this;
  override once(
    event: "exit",
    listener: (code: number | null, signal: string | null) => void
  ): this;
  override once(event: "error", listener: (error: Error) => void): this;
  override once(event: "spawn", listener: () => void): this;
  // biome-ignore lint/suspicious/noExplicitAny: Required for EventEmitter overload compatibility
  override once(event: string, listener: (...args: any[]) => void): this {
    return super.once(event, listener);
  }

  override emit(event: "stdout", chunk: StreamChunk): boolean;
  override emit(event: "stderr", chunk: StreamChunk): boolean;
  override emit(
    event: "exit",
    code: number | null,
    signal: string | null
  ): boolean;
  override emit(event: "error", error: Error): boolean;
  override emit(event: "spawn"): boolean;
  // biome-ignore lint/suspicious/noExplicitAny: Required for EventEmitter overload compatibility
  override emit(event: string, ...args: any[]): boolean {
    return super.emit(event, ...args);
  }
}

/**
 * Create a Claude Code process
 */
export function createClaudeProcess(
  command: string,
  args: string[],
  options: SpawnOptions
): ClaudeProcess {
  return new ClaudeProcess(command, args, options);
}

/**
 * Check if Claude Code is installed
 */
export async function isClaudeInstalled(
  command = "claude"
): Promise<{ installed: boolean; version?: string }> {
  return new Promise((resolve) => {
    const proc = spawn(command, ["--version"], {
      stdio: ["ignore", "pipe", "ignore"],
    });

    let output = "";

    proc.stdout?.on("data", (data: Buffer) => {
      output += data.toString();
    });

    proc.on("error", () => {
      resolve({ installed: false });
    });

    proc.on("exit", (code) => {
      if (code === 0) {
        const version = output.trim();
        resolve({ installed: true, version });
      } else {
        resolve({ installed: false });
      }
    });
  });
}
