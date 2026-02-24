import { z } from "zod";

/**
 * Session states
 */
export const SessionState = {
  INITIALIZING: "initializing",
  RUNNING: "running",
  PAUSED: "paused",
  COMPLETED: "completed",
  ERROR: "error",
} as const;

export type SessionState = (typeof SessionState)[keyof typeof SessionState];

/**
 * Session state schema
 */
export const SessionStateSchema = z.enum([
  "initializing",
  "running",
  "paused",
  "completed",
  "error",
]);

/**
 * Valid state transitions
 */
export const STATE_TRANSITIONS: Record<SessionState, SessionState[]> = {
  initializing: ["running", "error"],
  running: ["paused", "completed", "error"],
  paused: ["running", "completed", "error"],
  completed: [], // Terminal state
  error: [], // Terminal state
};

/**
 * Session configuration
 */
export interface SessionConfig {
  /** Branch name */
  branch?: string;
  /** Device ID */
  deviceId: string;
  /** Environment variables */
  env?: Record<string, string>;
  /** Maximum tokens */
  maxTokens?: number;
  /** Model to use */
  model?: string;
  /** Repository path */
  repositoryPath: string;
  /** Session ID */
  sessionId: string;
  /** Timeout in milliseconds */
  timeoutMs?: number;
  /** User ID */
  userId: string;
  /** Worktree path (if using worktrees) */
  worktreePath?: string;
}

/**
 * Session configuration schema
 */
export const SessionConfigSchema = z.object({
  sessionId: z.string().uuid(),
  repositoryPath: z.string(),
  worktreePath: z.string().optional(),
  branch: z.string().optional(),
  deviceId: z.string().uuid(),
  userId: z.string().uuid(),
  model: z.string().optional(),
  maxTokens: z.number().optional(),
  timeoutMs: z.number().optional(),
  env: z.record(z.string(), z.string()).optional(),
});

/**
 * Session metadata
 */
export interface SessionMetadata {
  /** Branch name */
  branch?: string;
  /** Device ID */
  deviceId: string;
  /** Total duration in milliseconds */
  durationMs?: number;
  /** End time (if completed/error) */
  endedAt?: Date;
  /** Error message (if error state) */
  error?: string;
  /** Last activity time */
  lastActivityAt: Date;
  /** Message count */
  messageCount: number;
  /** Process ID */
  pid?: number;
  /** Repository URL */
  repositoryUrl?: string;
  /** Session ID */
  sessionId: string;
  /** Start time */
  startedAt: Date;
  /** Current state */
  state: SessionState;
  /** User ID */
  userId: string;
  /** Worktree path */
  worktreePath?: string;
}

/**
 * Message types for session communication
 */
export const MessageType = {
  /** User input to Claude */
  INPUT: "input",
  /** Claude output */
  OUTPUT: "output",
  /** Control message (typing, ready, etc.) */
  CONTROL: "control",
  /** Error message */
  ERROR: "error",
  /** System message */
  SYSTEM: "system",
} as const;

export type MessageType = (typeof MessageType)[keyof typeof MessageType];

/**
 * Session message
 */
export interface SessionMessage {
  /** Whether message has been acknowledged */
  acknowledged: boolean;
  /** Message content */
  content: string;
  /** Unique message ID */
  id: string;
  /** Retry count */
  retryCount: number;
  /** Sequence number for ordering */
  sequence: number;
  /** Session ID */
  sessionId: string;
  /** Timestamp */
  timestamp: Date;
  /** Message type */
  type: MessageType;
}

/**
 * Session message schema
 */
export const SessionMessageSchema = z.object({
  id: z.string().uuid(),
  sessionId: z.string().uuid(),
  type: z.enum(["input", "output", "control", "error", "system"]),
  content: z.string(),
  timestamp: z.date(),
  sequence: z.number(),
  acknowledged: z.boolean(),
  retryCount: z.number(),
});

/**
 * Process spawn options
 */
export interface SpawnOptions {
  /** Working directory */
  cwd: string;
  /** Environment variables */
  env?: Record<string, string>;
  /** Maximum memory in bytes */
  maxMemory?: number;
  /** Timeout in milliseconds */
  timeoutMs?: number;
}

/**
 * Process info
 */
export interface ProcessInfo {
  /** End time */
  endedAt?: Date;
  /** Exit code (if exited) */
  exitCode?: number;
  /** Process ID */
  pid: number;
  /** Whether process is running */
  running: boolean;
  /** Exit signal (if killed) */
  signal?: string;
  /** Start time */
  startedAt: Date;
}

/**
 * Stream chunk
 */
export interface StreamChunk {
  /** Chunk data */
  data: Buffer;
  /** Timestamp */
  timestamp: Date;
  /** Stream type */
  type: "stdout" | "stderr";
}

/**
 * Session event types
 */
export const SessionEventType = {
  STATE_CHANGE: "state_change",
  MESSAGE: "message",
  OUTPUT: "output",
  ERROR: "error",
  PROCESS_EXIT: "process_exit",
} as const;

export type SessionEventType =
  (typeof SessionEventType)[keyof typeof SessionEventType];

/**
 * Session event
 */
export interface SessionEvent {
  data: unknown;
  sessionId: string;
  timestamp: Date;
  type: SessionEventType;
}

/**
 * State change event data
 */
export interface StateChangeData {
  newState: SessionState;
  previousState: SessionState;
  reason?: string;
}

/**
 * Session manager configuration
 */
export interface SessionManagerConfig {
  /** Claude Code arguments */
  claudeArgs: string[];
  /** Claude Code command */
  claudeCommand: string;
  /** Default session timeout in milliseconds */
  defaultTimeoutMs: number;
  /** Heartbeat interval in milliseconds */
  heartbeatIntervalMs: number;
  /** Maximum concurrent sessions */
  maxConcurrentSessions: number;
  /** Message retry attempts */
  maxRetryAttempts: number;
  /** Message retry delay in milliseconds */
  retryDelayMs: number;
}

/**
 * Default session manager configuration
 */
export const DEFAULT_SESSION_MANAGER_CONFIG: SessionManagerConfig = {
  maxConcurrentSessions: 5,
  defaultTimeoutMs: 30 * 60 * 1000, // 30 minutes
  maxRetryAttempts: 3,
  retryDelayMs: 1000,
  heartbeatIntervalMs: 30_000,
  claudeCommand: "claude",
  claudeArgs: ["--dangerously-skip-permissions"],
};

/**
 * Session result
 */
export interface SessionResult<T> {
  data?: T;
  error?: string;
  success: boolean;
}
