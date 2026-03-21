import {
  buildConversationTimeline,
  type ConversationBlock,
  type ConversationQuestion,
  type ConversationQuestionOption,
  type ConversationRole,
} from "./conversationTimeline";
import type { SessionMessage } from "./types";

export type SessionConversationProvider = "claude" | "codex" | "custom";
export type SessionConversationRole = ConversationRole | "result";
export type SessionConversationTone =
  | "neutral"
  | "running"
  | "succeeded"
  | "failed"
  | "warning";

export interface SessionConversationCommandBlock {
  id: string;
  kind: "command";
  command: string;
  exitCode: number | null;
  output: string | null;
  status: string;
}

export interface SessionConversationNoteBlock {
  id: string;
  kind: "note";
  kicker: string;
  meta: string[];
  text: string;
  tone: SessionConversationTone;
}

export interface SessionConversationCompactBoundaryBlock {
  id: string;
  kind: "compactBoundary";
  text: string;
}

export interface SessionConversationResultBlock {
  id: string;
  kind: "result";
  meta: string[];
  text: string;
  tone: SessionConversationTone;
}

export type SessionConversationBlock =
  | ConversationBlock
  | SessionConversationCompactBoundaryBlock
  | SessionConversationCommandBlock
  | SessionConversationNoteBlock
  | SessionConversationResultBlock;

export interface SessionConversationRow {
  blocks: SessionConversationBlock[];
  id: string;
  messageId: string;
  provider: SessionConversationProvider;
  role: SessionConversationRole;
  sequenceNumber: number;
}

export function buildSessionConversationTimeline(
  messages: SessionMessage[],
  provider: SessionConversationProvider
): SessionConversationRow[] {
  if (provider === "codex") {
    return buildCodexConversationTimeline(messages);
  }

  const normalizedMessages = normalizeClaudeMessages(messages);
  const resultMessageIds = new Set(
    normalizedMessages
      .filter((message) => isClaudeResultMessage(message))
      .map((message) => message.id)
  );
  const baseRows = dedupeSessionConversationRows(
    buildConversationTimeline(normalizedMessages)
      .map((row): SessionConversationRow => ({
        ...row,
        provider:
          provider === "custom"
            ? ("custom" as const)
            : ("claude" as const),
      }))
      .filter((row) => !resultMessageIds.has(row.messageId))
  );
  const compactBoundaryRows = normalizedMessages
    .map((message) => buildClaudeSystemRow(message, provider))
    .filter(isPresent);
  const resultRows = normalizedMessages
    .map((message) => buildClaudeResultRow(message, provider))
    .filter(isPresent);

  return dedupeSessionConversationRows([...baseRows, ...compactBoundaryRows, ...resultRows]).sort(
    (left, right) => left.sequenceNumber - right.sequenceNumber
  );
}

export function sessionConversationBlockSemanticType(
  block: SessionConversationBlock
) {
  switch (block.kind) {
    case "tool":
      return "toolCall";
    case "subagent":
      return "subAgent";
    case "compactBoundary":
      return "compactBoundary";
    case "command":
      return "command";
    case "note":
      return "note";
    case "result":
      return "result";
    default:
      return block.kind;
  }
}

function buildCodexConversationTimeline(messages: SessionMessage[]) {
  const rows: SessionConversationRow[] = [];
  const orderedMessages = messages
    .slice()
    .sort(
      (left, right) =>
        normalizeSequenceNumber(left.sequence_number) -
        normalizeSequenceNumber(right.sequence_number)
    );

  for (const message of orderedMessages) {
    const normalized = normalizeMessageContent(message.content);
    if (normalized.kind === "text") {
      const text = sanitizeText(normalized.value);
      if (!text) {
        continue;
      }

      rows.push({
        blocks: [
          {
            id: `${message.id}-text`,
            kind: "text",
            text,
          },
        ],
        id: message.id,
        messageId: message.id,
        provider: "codex",
        role: "user",
        sequenceNumber: normalizeSequenceNumber(message.sequence_number),
      });
      continue;
    }

    const payload = normalized.value;
    const messageType = readString(payload.type)?.toLowerCase() ?? "";
    const item = readRecord(payload.item);
    const itemType = readString(item?.type)?.toLowerCase() ?? "";
    const row: SessionConversationRow = {
      blocks: [],
      id: message.id,
      messageId: message.id,
      provider: "codex",
      role: "assistant",
      sequenceNumber: normalizeSequenceNumber(message.sequence_number),
    };

    const questionBlocks = parseQuestionBlocksFromUnknown(
      payload,
      `${message.id}-question`
    );
    if (questionBlocks.length > 0) {
      row.blocks.push(...questionBlocks);
      row.role = "assistant";
    }

    if (messageType === "thread.started") {
      row.role = "system";
      row.blocks.push({
        id: `${message.id}-thread`,
        kind: "note",
        kicker: "Thread",
        meta: [],
        text: readString(payload.thread_id)
          ? `Codex resumed thread ${String(payload.thread_id)}.`
          : "Codex started a thread.",
        tone: "neutral",
      });
    } else if (messageType === "turn.started") {
      row.role = "system";
      row.blocks.push({
        id: `${message.id}-turn-started`,
        kind: "note",
        kicker: "Turn",
        meta: [],
        text: "Codex started a new turn.",
        tone: "running",
      });
    } else if (messageType === "turn.completed") {
      row.role = "system";
      const usage = readRecord(payload.usage);
      const meta = [
        formatMetric("Input", numberFromUnknown(usage?.input_tokens)),
        formatMetric("Cached", numberFromUnknown(usage?.cached_input_tokens)),
        formatMetric("Output", numberFromUnknown(usage?.output_tokens)),
      ].filter((value): value is string => Boolean(value));
      row.blocks.push({
        id: `${message.id}-turn-completed`,
        kind: "note",
        kicker: "Turn",
        meta,
        text: "Codex finished the turn.",
        tone: "succeeded",
      });
    } else if (
      (messageType === "item.started" || messageType === "item.completed") &&
      itemType === "command_execution"
    ) {
      row.role = "assistant";
      row.blocks.push({
        command: sanitizeText(readString(item?.command)) ?? "",
        exitCode: numberFromUnknown(item?.exit_code) ?? null,
        id: `${message.id}-command`,
        kind: "command",
        output: sanitizeText(readString(item?.aggregated_output)),
        status: readString(item?.status) ?? "completed",
      });
    } else if (messageType === "item.completed" && itemType === "agent_message") {
      const text = sanitizeText(readString(item?.text));
      if (text) {
        row.role = "assistant";
        row.blocks.push({
          id: `${message.id}-agent-message`,
          kind: "text",
          text,
        });
      }
    } else if (messageType === "stderr") {
      const warningText =
        sanitizeText(readString(payload.message)) ??
        sanitizeText(readString(payload.text)) ??
        sanitizeText(readString(payload.error));
      if (warningText) {
        row.role = "system";
        row.blocks.push({
          id: `${message.id}-warning`,
          kind: "note",
          kicker: "Warning",
          meta: [],
          text: warningText,
          tone: "warning",
        });
      }
    } else {
      const fallbackText =
        sanitizeText(readString(payload.message)) ??
        sanitizeText(readString(payload.text)) ??
        sanitizeText(readString(item?.text));
      if (fallbackText) {
        row.role = itemType === "agent_message" ? "assistant" : "system";
        row.blocks.push({
          id: `${message.id}-fallback`,
          kind: "note",
          kicker: "Activity",
          meta: [],
          text: fallbackText,
          tone: "neutral",
        });
      }
    }

    if (row.blocks.length > 0) {
      rows.push(row);
    }
  }

  return rows;
}

function normalizeClaudeMessages(messages: SessionMessage[]) {
  return messages.map((message) => {
    const normalized = normalizeMessageContent(message.content);
    if (normalized.kind !== "object") {
      return message;
    }

    const payload = normalized.value;
    const messageType = readString(payload.type)?.toLowerCase();
    const canonicalAssistantId = sanitizeText(
      readString(readRecord(payload.message)?.id)
    );
    if (messageType === "assistant" && canonicalAssistantId) {
      return {
        ...message,
        id: canonicalAssistantId,
      };
    }

    if (messageType === "user_prompt_command") {
      return {
        ...message,
        content: readString(payload.message) ?? message.content,
      };
    }

    if (messageType === "user") {
      const contentBlocks = readArray(readRecord(payload.message)?.content);
      const onlyToolResults =
        contentBlocks.length > 0 &&
        contentBlocks.every(
          (block) =>
            readString(readRecord(block)?.type)?.toLowerCase() === "tool_result"
        );

      const parentToolUseId = sanitizeText(readString(payload.parent_tool_use_id));
      if (onlyToolResults || parentToolUseId) {
        return {
          ...message,
          content: JSON.stringify({
            message: {
              content: [],
            },
            type: "user",
          }),
        };
      }
    }

    return message;
  });
}

function buildClaudeSystemRow(
  message: SessionMessage,
  provider: SessionConversationProvider
) {
  const normalized = normalizeMessageContent(message.content);
  if (normalized.kind !== "object") {
    return null;
  }

  const payload = normalized.value;
  const messageType = readString(payload.type)?.toLowerCase();
  const subtype = readString(payload.subtype)?.toLowerCase();
  if (messageType !== "system" || subtype !== "compact_boundary") {
    return null;
  }

  return {
    blocks: [
      {
        id: `${message.id}-compact-boundary`,
        kind: "compactBoundary" as const,
        text: "Conversation compacted.",
      },
    ],
    id: message.id,
    messageId: message.id,
        provider:
          provider === "custom"
            ? ("custom" as const)
            : ("claude" as const),
        role: "system" as const,
        sequenceNumber: normalizeSequenceNumber(message.sequence_number),
      };
}

function buildClaudeResultRow(
  message: SessionMessage,
  provider: SessionConversationProvider
) {
  const normalized = normalizeMessageContent(message.content);
  if (normalized.kind !== "object") {
    return null;
  }

  const payload = normalized.value;
  const messageType = readString(payload.type)?.toLowerCase();
  if (messageType !== "result") {
    return null;
  }

  const usage = readRecord(payload.usage);
  const permissionDenials = readArray(payload.permission_denials)
    .map((value) => sanitizeText(readString(value)))
    .filter((value): value is string => Boolean(value));
  const meta = [
    formatMetric("Input", numberFromUnknown(usage?.input_tokens)),
    formatMetric("Output", numberFromUnknown(usage?.output_tokens)),
    permissionDenials.length > 0
      ? `Denied ${permissionDenials.join(", ")}`
      : null,
  ].filter((value): value is string => Boolean(value));

  return {
    blocks: [
      {
        id: `${message.id}-result`,
        kind: "result" as const,
        meta,
        text: sanitizeText(readString(payload.result)) ?? "Completed",
        tone: Boolean(payload.is_error)
          ? ("failed" as const)
          : ("succeeded" as const),
      },
    ],
    id: message.id,
    messageId: message.id,
        provider:
          provider === "custom"
            ? ("custom" as const)
            : ("claude" as const),
        role: "result" as const,
        sequenceNumber: normalizeSequenceNumber(message.sequence_number),
      };
}

function isClaudeResultMessage(message: SessionMessage) {
  const normalized = normalizeMessageContent(message.content);
  return (
    normalized.kind === "object" &&
    readString(normalized.value.type)?.toLowerCase() === "result"
  );
}

function dedupeSessionConversationRows(rows: SessionConversationRow[]) {
  const rowsById = new Map<string, SessionConversationRow>();
  rows.forEach((row) => {
    const existing = rowsById.get(row.id);
    if (!existing) {
      rowsById.set(row.id, row);
      return;
    }

    const blocksById = new Map<string, SessionConversationBlock>();
    existing.blocks.forEach((block) => {
      blocksById.set(block.id, block);
    });
    row.blocks.forEach((block) => {
      blocksById.set(block.id, block);
    });

    rowsById.set(row.id, {
      ...row,
      blocks: Array.from(blocksById.values()),
    });
  });
  return Array.from(rowsById.values());
}

function isPresent<T>(value: T | null): value is T {
  return value !== null;
}

function normalizeMessageContent(value: unknown) {
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) {
      return { kind: "text" as const, value: "" };
    }

    try {
      const parsed = JSON.parse(trimmed) as unknown;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return {
          kind: "object" as const,
          value: parsed as Record<string, unknown>,
        };
      }
    } catch {
      return { kind: "text" as const, value };
    }

    return { kind: "text" as const, value };
  }

  if (value && typeof value === "object" && !Array.isArray(value)) {
    return {
      kind: "object" as const,
      value: value as Record<string, unknown>,
    };
  }

  return { kind: "text" as const, value: String(value ?? "") };
}

function parseQuestionBlocksFromUnknown(
  value: unknown,
  idPrefix: string
): SessionConversationBlock[] {
  const request = findQuestionRequest(value, 0);
  if (!request) {
    return [];
  }

  const questions = normalizeQuestionInput(request.input);
  return questions.map((question, index) => ({
    id: `${idPrefix}-${index}`,
    kind: "question",
    question,
  }));
}

function findQuestionRequest(
  value: unknown,
  depth: number
): { input: unknown } | null {
  if (depth > 6 || value == null) {
    return null;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const result = findQuestionRequest(item, depth + 1);
      if (result) {
        return result;
      }
    }
    return null;
  }

  if (typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, unknown>;
  const toolName =
    readString(record.name)?.toLowerCase() ??
    readString(record.tool_name)?.toLowerCase() ??
    null;
  if (toolName === "request_user_input") {
    return {
      input:
        record.input ??
        parseArguments(readString(record.arguments)) ??
        record.args ??
        null,
    };
  }

  for (const nested of Object.values(record)) {
    const result = findQuestionRequest(nested, depth + 1);
    if (result) {
      return result;
    }
  }

  return null;
}

function normalizeQuestionInput(inputValue: unknown): ConversationQuestion[] {
  const input = readRecord(inputValue);
  const rawQuestions = Array.isArray(input?.questions)
    ? input.questions
    : typeof input?.question === "string"
      ? [input]
      : [];

  return rawQuestions
    .map((question, index) => parseQuestion(question, `codex-question-${index}`))
    .filter((question): question is ConversationQuestion => question !== null);
}

function parseQuestion(
  value: unknown,
  fallbackId: string
): ConversationQuestion | null {
  const record = readRecord(value);
  const question =
    sanitizeText(readString(record?.question)) ??
    sanitizeText(readString(record?.prompt));
  if (!record || !question) {
    return null;
  }

  const options = readArray(record.options)
    .map(parseQuestionOption)
    .filter((option): option is ConversationQuestionOption => option !== null);

  return {
    allowsMultiSelect: Boolean(
      record.multi_select ?? record.allows_multi_select ?? record.multiSelect
    ),
    allowsTextInput:
      record.allows_text_input == null && record.allow_text_input == null
        ? true
        : Boolean(record.allows_text_input ?? record.allow_text_input),
    header:
      sanitizeText(readString(record.header)) ??
      sanitizeText(readString(record.label)),
    id: sanitizeText(readString(record.id)) ?? fallbackId,
    options,
    question,
  };
}

function parseQuestionOption(value: unknown): ConversationQuestionOption | null {
  if (typeof value === "string") {
    const label = sanitizeText(value);
    if (!label) {
      return null;
    }

    return {
      description: null,
      label,
      value: label,
    };
  }

  const record = readRecord(value);
  const label =
    sanitizeText(readString(record?.label)) ??
    sanitizeText(readString(record?.title)) ??
    sanitizeText(readString(record?.value));
  if (!record || !label) {
    return null;
  }

  return {
    description: sanitizeText(readString(record.description)),
    label,
    value:
      sanitizeText(readString(record.value)) ??
      sanitizeText(readString(record.id)) ??
      label,
  };
}

function normalizeSequenceNumber(value: number | string) {
  const numberValue = Number(value);
  return Number.isFinite(numberValue) ? numberValue : 0;
}

function readString(value: unknown) {
  return typeof value === "string" ? value : null;
}

function readRecord(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function readArray(value: unknown) {
  return Array.isArray(value) ? value : [];
}

function sanitizeText(value: string | null | undefined) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function parseArguments(value: string | null) {
  if (!value) {
    return null;
  }

  try {
    return JSON.parse(value) as unknown;
  } catch {
    return null;
  }
}

function numberFromUnknown(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return null;
}

function formatMetric(label: string, value: number | null) {
  if (value == null) {
    return null;
  }

  return `${label} ${value.toLocaleString("en-US")}`;
}
