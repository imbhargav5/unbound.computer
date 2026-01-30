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
  /** Session ID */
  sessionId: string;
  /** Repository path */
  repositoryPath: string;
  /** Worktree path (if using worktrees) */
  worktreePath?: string;
  /** Branch name */
  branch?: string;
  /** Device ID */
  deviceId: string;
  /** User ID */
  userId: string;
  /** Model to use */
  model?: string;
  /** Maximum tokens */
  maxTokens?: number;
  /** Timeout in milliseconds */
  timeoutMs?: number;
  /** Environment variables */
  env?: Record<string, string>;
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
  env: z.record(z.string()).optional(),
});

/**
 * Session metadata
 */
export interface SessionMetadata {
  /** Session ID */
  sessionId: string;
  /** Current state */
  state: SessionState;
  /** Repository URL */
  repositoryUrl?: string;
  /** Worktree path */
  worktreePath?: string;
  /** Branch name */
  branch?: string;
  /** Device ID */
  deviceId: string;
  /** User ID */
  userId: string;
  /** Start time */
  startedAt: Date;
  /** Last activity time */
  lastActivityAt: Date;
  /** End time (if completed/error) */
  endedAt?: Date;
  /** Total duration in milliseconds */
  durationMs?: number;
  /** Error message (if error state) */
  error?: string;
  /** Process ID */
  pid?: number;
  /** Message count */
  messageCount: number;
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
  /** Unique message ID */
  id: string;
  /** Session ID */
  sessionId: string;
  /** Message type */
  type: MessageType;
  /** Message content */
  content: string;
  /** Timestamp */
  timestamp: Date;
  /** Sequence number for ordering */
  sequence: number;
  /** Whether message has been acknowledged */
  acknowledged: boolean;
  /** Retry count */
  retryCount: number;
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
  /** Timeout in milliseconds */
  timeoutMs?: number;
  /** Maximum memory in bytes */
  maxMemory?: number;
}

/**
 * Process info
 */
export interface ProcessInfo {
  /** Process ID */
  pid: number;
  /** Whether process is running */
  running: boolean;
  /** Exit code (if exited) */
  exitCode?: number;
  /** Exit signal (if killed) */
  signal?: string;
  /** Start time */
  startedAt: Date;
  /** End time */
  endedAt?: Date;
}

/**
 * Stream chunk
 */
export interface StreamChunk {
  /** Stream type */
  type: "stdout" | "stderr";
  /** Chunk data */
  data: Buffer;
  /** Timestamp */
  timestamp: Date;
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
  type: SessionEventType;
  sessionId: string;
  timestamp: Date;
  data: unknown;
}

/**
 * State change event data
 */
export interface StateChangeData {
  previousState: SessionState;
  newState: SessionState;
  reason?: string;
}

/**
 * Session manager configuration
 */
export interface SessionManagerConfig {
  /** Maximum concurrent sessions */
  maxConcurrentSessions: number;
  /** Default session timeout in milliseconds */
  defaultTimeoutMs: number;
  /** Message retry attempts */
  maxRetryAttempts: number;
  /** Message retry delay in milliseconds */
  retryDelayMs: number;
  /** Heartbeat interval in milliseconds */
  heartbeatIntervalMs: number;
  /** Claude Code command */
  claudeCommand: string;
  /** Claude Code arguments */
  claudeArgs: string[];
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
  success: boolean;
  data?: T;
  error?: string;
}
