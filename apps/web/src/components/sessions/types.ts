/**
 * Tool use representation in the UI
 */
export interface ToolUse {
  duration?: number;
  id: string;
  input?: unknown;
  name: string;
  output?: unknown;
  status: "pending" | "running" | "completed" | "error";
}

/**
 * Session message representation in the UI
 */
export interface SessionMessage {
  content?: string;
  id: string;
  role: "user" | "assistant";
  timestamp: string;
  toolUses?: ToolUse[];
}

/**
 * Coding session status
 */
export type SessionStatus = "active" | "paused" | "ended";

/**
 * Full session data for the UI
 */
export interface Session {
  branchName: string;
  deviceName: string;
  endedAt?: string;
  id: string;
  repositoryName: string;
  startedAt: string;
  status: SessionStatus;
}
