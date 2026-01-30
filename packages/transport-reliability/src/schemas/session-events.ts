import { z } from "zod";
import { BaseUnboundEvent } from "./base";

/* ---------------- SESSION BASE ---------------- */

// sessionId uses flexible string validation to support both UUID and ULID formats
// (existing sessions may use UUID format)
export const SessionBaseEvent = BaseUnboundEvent.extend({
  plane: z.literal("SESSION"),
  sessionId: z.string().min(1),
  sessionEventType: z.enum([
    "REMOTE_COMMAND",
    "EXECUTOR_UPDATE",
    "LOCAL_EXECUTION_COMMAND",
  ]),
});

/* ---------------- SESSION CONTROL COMMANDS ---------------- */

export const SessionPauseCommand = SessionBaseEvent.extend({
  type: z.literal("SESSION_PAUSE_COMMAND"),
  payload: z.object({}),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

export const SessionResumeCommand = SessionBaseEvent.extend({
  type: z.literal("SESSION_RESUME_COMMAND"),
  payload: z.object({}),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

export const SessionStopCommand = SessionBaseEvent.extend({
  type: z.literal("SESSION_STOP_COMMAND"),
  payload: z.object({
    force: z.boolean().optional(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

export const SessionCancelCommand = SessionBaseEvent.extend({
  type: z.literal("SESSION_CANCEL_COMMAND"),
  payload: z.object({
    reason: z.string().optional(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

/* ---------------- USER INPUT COMMANDS ---------------- */

export const AttachmentSchema = z.object({
  type: z.enum(["image", "file", "url"]),
  data: z.string(),
  mimeType: z.string().optional(),
  filename: z.string().optional(),
});

export const UserPromptCommand = SessionBaseEvent.extend({
  type: z.literal("USER_PROMPT_COMMAND"),
  payload: z.object({
    content: z.string(),
    attachments: z.array(AttachmentSchema).optional(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

export const UserConfirmationCommand = SessionBaseEvent.extend({
  type: z.literal("USER_CONFIRMATION_COMMAND"),
  payload: z.object({
    questionId: z.string(),
    confirmed: z.boolean(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

export const McqResponseCommand = SessionBaseEvent.extend({
  type: z.literal("MCQ_RESPONSE_COMMAND"),
  payload: z.object({
    questionId: z.string(),
    selectedOptionIds: z.array(z.string()),
    customAnswer: z.string().optional(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

export const ToolApprovalCommand = SessionBaseEvent.extend({
  type: z.literal("TOOL_APPROVAL_COMMAND"),
  payload: z.object({
    toolUseId: z.string(),
    approved: z.boolean(),
    modifiedInput: z.string().optional(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

/* ---------------- WORKTREE/CONFLICTS COMMANDS ---------------- */

export const WorktreeCreateCommand = SessionBaseEvent.extend({
  type: z.literal("WORKTREE_CREATE_COMMAND"),
  payload: z.object({
    repoId: z.string(),
    branch: z.string(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

export const ConflictsFixCommand = SessionBaseEvent.extend({
  type: z.literal("CONFLICTS_FIX_COMMAND"),
  payload: z.object({
    repoId: z.string(),
    worktreeId: z.string(),
  }),
  sessionEventType: z.literal("REMOTE_COMMAND"),
});

/* ---------------- EXECUTION UPDATES ---------------- */

export const ExecutionStartedUpdate = SessionBaseEvent.extend({
  type: z.literal("EXECUTION_STARTED"),
  payload: z.object({}),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const OutputChunkUpdate = SessionBaseEvent.extend({
  type: z.literal("OUTPUT_CHUNK"),
  payload: z.object({
    text: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ExecutionCompletedUpdate = SessionBaseEvent.extend({
  type: z.literal("EXECUTION_COMPLETED"),
  payload: z.object({
    success: z.boolean(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const WorktreeAddedUpdate = SessionBaseEvent.extend({
  type: z.literal("WORKTREE_ADDED"),
  payload: z.object({
    repoId: z.string(),
    worktreeId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const RepositoryAddedUpdate = SessionBaseEvent.extend({
  type: z.literal("REPOSITORY_ADDED"),
  payload: z.object({
    repoId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const RepositoryRemovedUpdate = SessionBaseEvent.extend({
  type: z.literal("REPOSITORY_REMOVED"),
  payload: z.object({
    repoId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ConflictsFixedUpdate = SessionBaseEvent.extend({
  type: z.literal("CONFLICTS_FIXED"),
  payload: z.object({
    repoId: z.string(),
    worktreeId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ConflictsFixFailedUpdate = SessionBaseEvent.extend({
  type: z.literal("CONFLICTS_FIX_FAILED"),
  payload: z.object({
    repoId: z.string(),
    worktreeId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const GitPushCompletedUpdate = SessionBaseEvent.extend({
  type: z.literal("GIT_PUSH_COMPLETED"),
  payload: z.object({
    repoId: z.string(),
    worktreeId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const GitPushFailedUpdate = SessionBaseEvent.extend({
  type: z.literal("GIT_PUSH_FAILED"),
  payload: z.object({
    repoId: z.string(),
    worktreeId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ConflictsFoundUpdate = SessionBaseEvent.extend({
  type: z.literal("CONFLICTS_FOUND"),
  payload: z.object({
    repoId: z.string(),
    worktreeId: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- TOOL EXECUTION UPDATES ---------------- */

export const ToolStartedUpdate = SessionBaseEvent.extend({
  type: z.literal("TOOL_STARTED"),
  payload: z.object({
    toolUseId: z.string(),
    toolName: z.string(),
    input: z.string().optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ToolOutputChunkUpdate = SessionBaseEvent.extend({
  type: z.literal("TOOL_OUTPUT_CHUNK"),
  payload: z.object({
    toolUseId: z.string(),
    chunk: z.string(),
    sequenceNumber: z.number(),
    isComplete: z.boolean(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ToolCompletedUpdate = SessionBaseEvent.extend({
  type: z.literal("TOOL_COMPLETED"),
  payload: z.object({
    toolUseId: z.string(),
    toolName: z.string(),
    output: z.string().optional(),
    success: z.boolean(),
    durationMs: z.number(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ToolFailedUpdate = SessionBaseEvent.extend({
  type: z.literal("TOOL_FAILED"),
  payload: z.object({
    toolUseId: z.string(),
    toolName: z.string(),
    error: z.string(),
    errorCode: z.string().optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ToolApprovalRequiredUpdate = SessionBaseEvent.extend({
  type: z.literal("TOOL_APPROVAL_REQUIRED"),
  payload: z.object({
    toolUseId: z.string(),
    toolName: z.string(),
    input: z.string(),
    description: z.string().optional(),
    risk: z.enum(["low", "medium", "high"]).optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- STREAMING STATE UPDATES ---------------- */

export const StreamingThinkingUpdate = SessionBaseEvent.extend({
  type: z.literal("STREAMING_THINKING"),
  payload: z.object({
    thinkingContent: z.string().optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const StreamingGeneratingUpdate = SessionBaseEvent.extend({
  type: z.literal("STREAMING_GENERATING"),
  payload: z.object({
    contentType: z.enum(["text", "tool_use"]),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const StreamingWaitingUpdate = SessionBaseEvent.extend({
  type: z.literal("STREAMING_WAITING"),
  payload: z.object({
    reason: z.enum(["user_input", "tool_execution", "rate_limit", "api_call"]),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const StreamingIdleUpdate = SessionBaseEvent.extend({
  type: z.literal("STREAMING_IDLE"),
  payload: z.object({}),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- FILE CHANGE UPDATES ---------------- */

export const FileCreatedUpdate = SessionBaseEvent.extend({
  type: z.literal("FILE_CREATED"),
  payload: z.object({
    filePath: z.string(),
    content: z.string().optional(),
    linesAdded: z.number(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const FileModifiedUpdate = SessionBaseEvent.extend({
  type: z.literal("FILE_MODIFIED"),
  payload: z.object({
    filePath: z.string(),
    diff: z.string().optional(),
    linesAdded: z.number(),
    linesRemoved: z.number(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const FileDeletedUpdate = SessionBaseEvent.extend({
  type: z.literal("FILE_DELETED"),
  payload: z.object({
    filePath: z.string(),
    linesRemoved: z.number(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const FileRenamedUpdate = SessionBaseEvent.extend({
  type: z.literal("FILE_RENAMED"),
  payload: z.object({
    oldPath: z.string(),
    newPath: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- SESSION HEALTH UPDATES ---------------- */

export const SessionHeartbeatUpdate = SessionBaseEvent.extend({
  type: z.literal("SESSION_HEARTBEAT"),
  payload: z.object({
    processAlive: z.boolean(),
    memoryUsageMb: z.number().optional(),
    cpuPercent: z.number().optional(),
    uptime: z.number(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const SessionStateEnum = z.enum([
  "initializing",
  "running",
  "paused",
  "completed",
  "error",
]);

export const SessionStateChangedUpdate = SessionBaseEvent.extend({
  type: z.literal("SESSION_STATE_CHANGED"),
  payload: z.object({
    previousState: SessionStateEnum,
    newState: SessionStateEnum,
    reason: z.string().optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const ConnectionQualityUpdate = SessionBaseEvent.extend({
  type: z.literal("CONNECTION_QUALITY_UPDATE"),
  payload: z.object({
    latencyMs: z.number(),
    packetLossPercent: z.number(),
    quality: z.enum(["excellent", "good", "fair", "poor"]),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- ERROR/WARNING UPDATES ---------------- */

export const SessionErrorUpdate = SessionBaseEvent.extend({
  type: z.literal("SESSION_ERROR"),
  payload: z.object({
    code: z.string(),
    message: z.string(),
    details: z.string().optional(),
    recoverable: z.boolean(),
    action: z.enum(["retry", "restart", "abort", "ignore"]).optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const SessionWarningUpdate = SessionBaseEvent.extend({
  type: z.literal("SESSION_WARNING"),
  payload: z.object({
    code: z.string(),
    message: z.string(),
    details: z.string().optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const RateLimitWarningUpdate = SessionBaseEvent.extend({
  type: z.literal("RATE_LIMIT_WARNING"),
  payload: z.object({
    retryAfterMs: z.number(),
    limitType: z.enum(["requests", "tokens", "concurrent"]),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- TODO UPDATES ---------------- */

export const TodoItemSchema = z.object({
  id: z.string(),
  content: z.string(),
  status: z.enum(["pending", "in_progress", "completed"]),
});

export const TodoListUpdatedUpdate = SessionBaseEvent.extend({
  type: z.literal("TODO_LIST_UPDATED"),
  payload: z.object({
    items: z.array(TodoItemSchema),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const TodoItemUpdatedUpdate = SessionBaseEvent.extend({
  type: z.literal("TODO_ITEM_UPDATED"),
  payload: z.object({
    itemId: z.string(),
    content: z.string(),
    previousStatus: z.enum(["pending", "in_progress", "completed"]),
    newStatus: z.enum(["pending", "in_progress", "completed"]),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- QUESTION EVENTS ---------------- */

export const QuestionOptionSchema = z.object({
  id: z.string(),
  label: z.string(),
  description: z.string().optional(),
});

export const QuestionAskedUpdate = SessionBaseEvent.extend({
  type: z.literal("QUESTION_ASKED"),
  payload: z.object({
    questionId: z.string(),
    questionType: z.enum(["confirmation", "mcq", "text_input"]),
    question: z.string(),
    options: z.array(QuestionOptionSchema).optional(),
    allowsMultiSelect: z.boolean().optional(),
    allowsCustomAnswer: z.boolean().optional(),
    defaultValue: z.string().optional(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

export const QuestionAnsweredUpdate = SessionBaseEvent.extend({
  type: z.literal("QUESTION_ANSWERED"),
  payload: z.object({
    questionId: z.string(),
    selectedOptionIds: z.array(z.string()).optional(),
    textResponse: z.string().optional(),
    answeredBy: z.string(),
  }),
  sessionEventType: z.literal("EXECUTOR_UPDATE"),
});

/* ---------------- SESSION UNION ---------------- */

export const SessionEvent = z.discriminatedUnion("type", [
  // Session Control Commands
  SessionPauseCommand,
  SessionResumeCommand,
  SessionStopCommand,
  SessionCancelCommand,
  // User Input Commands
  UserPromptCommand,
  UserConfirmationCommand,
  McqResponseCommand,
  ToolApprovalCommand,
  // Worktree/Conflicts Commands
  WorktreeCreateCommand,
  ConflictsFixCommand,
  // Execution Updates
  ExecutionStartedUpdate,
  OutputChunkUpdate,
  ExecutionCompletedUpdate,
  WorktreeAddedUpdate,
  RepositoryAddedUpdate,
  RepositoryRemovedUpdate,
  ConflictsFixedUpdate,
  ConflictsFixFailedUpdate,
  GitPushCompletedUpdate,
  GitPushFailedUpdate,
  ConflictsFoundUpdate,
  // Tool Execution Updates
  ToolStartedUpdate,
  ToolOutputChunkUpdate,
  ToolCompletedUpdate,
  ToolFailedUpdate,
  ToolApprovalRequiredUpdate,
  // Streaming State Updates
  StreamingThinkingUpdate,
  StreamingGeneratingUpdate,
  StreamingWaitingUpdate,
  StreamingIdleUpdate,
  // File Change Updates
  FileCreatedUpdate,
  FileModifiedUpdate,
  FileDeletedUpdate,
  FileRenamedUpdate,
  // Session Health Updates
  SessionHeartbeatUpdate,
  SessionStateChangedUpdate,
  ConnectionQualityUpdate,
  // Error/Warning Updates
  SessionErrorUpdate,
  SessionWarningUpdate,
  RateLimitWarningUpdate,
  // Todo Updates
  TodoListUpdatedUpdate,
  TodoItemUpdatedUpdate,
  // Question Events
  QuestionAskedUpdate,
  QuestionAnsweredUpdate,
]);
