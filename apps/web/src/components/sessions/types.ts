/**
 * Tool use representation in the UI
 */
export interface ToolUse {
  id: string;
  name: string;
  input?: unknown;
  output?: unknown;
  status: "pending" | "running" | "completed" | "error";
  duration?: number;
}

/**
 * Session message representation in the UI
 */
export interface SessionMessage {
  id: string;
  role: "user" | "assistant";
  content?: string;
  toolUses?: ToolUse[];
  timestamp: string;
}

/**
 * Coding session status
 */
export type SessionStatus = "active" | "paused" | "ended";

/**
 * Full session data for the UI
 */
export interface Session {
  id: string;
  status: SessionStatus;
  repositoryName: string;
  branchName: string;
  deviceName: string;
  startedAt: string;
  endedAt?: string;
}
