import type { SessionMessage } from "./types";

export type ConversationRole = "user" | "assistant" | "system";
export type ConversationToolStatus = "running" | "completed" | "failed";
export type ConversationTodoStatus = "pending" | "in_progress" | "completed";

export interface ConversationQuestionOption {
  description: string | null;
  label: string;
  value: string;
}

export interface ConversationQuestion {
  allowsMultiSelect: boolean;
  allowsTextInput: boolean;
  header: string | null;
  id: string;
  options: ConversationQuestionOption[];
  question: string;
}

export interface ConversationTodoItem {
  content: string;
  id: string;
  status: ConversationTodoStatus;
}

export interface ConversationTodoList {
  id: string;
  items: ConversationTodoItem[];
  parentToolUseId: string | null;
  sourceToolUseId: string | null;
}

export interface ConversationTool {
  detail: string | null;
  id: string;
  input: string | null;
  output: string | null;
  parentToolUseId: string | null;
  preview: string | null;
  status: ConversationToolStatus;
  toolName: string;
  toolUseId: string | null;
}

export interface ConversationSubAgent {
  description: string;
  id: string;
  parentToolUseId: string;
  result: string | null;
  status: ConversationToolStatus;
  subagentType: string;
  tools: ConversationTool[];
}

export type ConversationBlock =
  | { id: string; kind: "text"; text: string }
  | { id: string; kind: "error"; message: string }
  | { id: string; kind: "question"; question: ConversationQuestion }
  | { id: string; kind: "subagent"; activity: ConversationSubAgent }
  | { id: string; kind: "todo"; todoList: ConversationTodoList }
  | { id: string; kind: "tool"; tool: ConversationTool };

export interface ConversationRow {
  blocks: ConversationBlock[];
  id: string;
  messageId: string;
  role: ConversationRole;
  sequenceNumber: number;
}

type ToolAnchor =
  | {
      blockIndex: number;
      kind: "standalone";
      rowIndex: number;
    }
  | {
      blockIndex: number;
      kind: "subagent";
      rowIndex: number;
      toolIndex: number;
    };

type BlockAnchor = {
  blockIndex: number;
  rowIndex: number;
};

type NormalizedPayload =
  | { kind: "object"; value: Record<string, unknown> }
  | { kind: "text"; value: string };

export function buildConversationTimeline(
  messages: SessionMessage[]
): ConversationRow[] {
  const orderedMessages = messages
    .slice()
    .sort(
      (left, right) =>
        normalizeSequenceNumber(left.sequence_number) -
        normalizeSequenceNumber(right.sequence_number)
    );

  const rows: ConversationRow[] = [];
  const toolAnchors = new Map<string, ToolAnchor>();
  const subAgentAnchors = new Map<string, BlockAnchor>();
  const todoAnchors = new Map<string, BlockAnchor>();
  const pendingChildTools = new Map<string, ConversationTool[]>();

  for (const message of orderedMessages) {
    const normalized = normalizePayload(message.content);
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
        role: "user",
        sequenceNumber: normalizeSequenceNumber(message.sequence_number),
      });
      continue;
    }

    const payload = resolvePayload(normalized.value);
    const messageType = readString(payload.type)?.toLowerCase() ?? null;

    if (!messageType) {
      const questionBlocks = parseQuestionBlocksFromPayload(
        payload,
        message.id
      );
      if (questionBlocks.length > 0) {
        rows.push({
          blocks: questionBlocks,
          id: message.id,
          messageId: message.id,
          role: "assistant",
          sequenceNumber: normalizeSequenceNumber(message.sequence_number),
        });
      }
      continue;
    }

    if (messageType === "assistant") {
      const row: ConversationRow = {
        blocks: [],
        id: message.id,
        messageId: message.id,
        role: "assistant",
        sequenceNumber: normalizeSequenceNumber(message.sequence_number),
      };
      const parentToolUseId = readString(payload.parent_tool_use_id);
      const contentBlocks = readArray(readRecord(payload.message)?.content);

      contentBlocks.forEach((block, blockIndex) => {
        const blockRecord = readRecord(block);
        const blockType = readString(blockRecord?.type)?.toLowerCase();
        if (!(blockRecord && blockType)) {
          return;
        }

        if (blockType === "text") {
          const text = sanitizeText(readString(blockRecord.text));
          if (text) {
            row.blocks.push({
              id: `${message.id}-text-${blockIndex}`,
              kind: "text",
              text,
            });
          }
          return;
        }

        if (blockType !== "tool_use") {
          return;
        }

        const toolName =
          readString(blockRecord.name) ??
          readString(blockRecord.tool_name) ??
          "Tool";
        const toolUseId =
          readString(blockRecord.id) ??
          readString(blockRecord.tool_use_id) ??
          readString(blockRecord.call_id);
        const toolParentId =
          readString(blockRecord.parent_tool_use_id) ?? parentToolUseId;
        const inputValue =
          blockRecord.input ??
          parseJsonValue(readString(blockRecord.arguments)) ??
          blockRecord.args ??
          null;

        if (isQuestionTool(toolName)) {
          row.blocks.push(
            ...parseQuestionBlocks(
              inputValue,
              `${message.id}-question-${blockIndex}`
            )
          );
          return;
        }

        if (toolName === "TodoWrite") {
          const todoList = parseTodoList(
            inputValue,
            `${message.id}-todo-${blockIndex}`,
            toolUseId,
            toolParentId
          );
          if (!todoList) {
            return;
          }
          const mergeKey = todoListMergeKey(todoList);
          if (mergeKey && todoAnchors.has(mergeKey)) {
            updateTodoAtAnchor(
              rows,
              todoAnchors.get(mergeKey) ?? null,
              todoList
            );
            return;
          }
          row.blocks.push({
            id: todoList.id,
            kind: "todo",
            todoList,
          });
          return;
        }

        if (toolName === "Task" && toolUseId) {
          const activity = createSubAgentActivity(
            inputValue,
            `${message.id}-subagent-${blockIndex}`,
            toolUseId
          );
          const pendingTools = pendingChildTools.get(toolUseId) ?? [];
          if (pendingTools.length > 0) {
            activity.tools = mergeTools(activity.tools, pendingTools);
            activity.status = deriveSubAgentStatus(
              activity.tools,
              activity.status
            );
            pendingChildTools.delete(toolUseId);
          }
          row.blocks.push({
            activity,
            id: activity.id,
            kind: "subagent",
          });
          return;
        }

        const tool = createConversationTool(
          toolName,
          toolUseId,
          toolParentId,
          inputValue,
          `${message.id}-tool-${blockIndex}`
        );

        if (toolParentId) {
          const anchor = subAgentAnchors.get(toolParentId);
          if (anchor) {
            appendToolToSubAgent(rows, anchor, tool, toolAnchors);
          } else {
            const pending = pendingChildTools.get(toolParentId) ?? [];
            pending.push(tool);
            pendingChildTools.set(toolParentId, mergeTools([], pending));
          }
          return;
        }

        row.blocks.push({
          id: tool.id,
          kind: "tool",
          tool,
        });
      });

      if (row.blocks.length > 0) {
        const rowIndex = rows.push(row) - 1;
        registerAnchorsForRow(
          rows,
          rowIndex,
          toolAnchors,
          subAgentAnchors,
          todoAnchors
        );
      }
      continue;
    }

    if (messageType === "user") {
      const row: ConversationRow = {
        blocks: [],
        id: message.id,
        messageId: message.id,
        role: "user",
        sequenceNumber: normalizeSequenceNumber(message.sequence_number),
      };
      const messageValue = payload.message;
      if (typeof messageValue === "string") {
        const text = sanitizeText(messageValue);
        if (text) {
          row.blocks.push({
            id: `${message.id}-text`,
            kind: "text",
            text,
          });
        }
      } else {
        const contentBlocks = readArray(readRecord(messageValue)?.content);
        contentBlocks.forEach((block, blockIndex) => {
          const blockRecord = readRecord(block);
          const blockType = readString(blockRecord?.type)?.toLowerCase();
          if (!(blockRecord && blockType)) {
            return;
          }

          if (blockType === "text") {
            const text = sanitizeText(readString(blockRecord.text));
            if (text) {
              row.blocks.push({
                id: `${message.id}-text-${blockIndex}`,
                kind: "text",
                text,
              });
            }
            return;
          }

          if (blockType !== "tool_result") {
            return;
          }

          const outputText = collectToolResultText(blockRecord);
          const toolUseId =
            readString(blockRecord.tool_use_id) ?? readString(blockRecord.id);
          const isError = Boolean(blockRecord.is_error);

          const didUpdateTool =
            toolUseId != null &&
            updateToolAtAnchor(
              rows,
              toolAnchors.get(toolUseId) ?? null,
              (tool) => ({
                ...tool,
                detail: outputText || tool.detail,
                output: outputText || tool.output,
                status: isError ? "failed" : "completed",
              })
            );

          if (!didUpdateTool && outputText) {
            if (isError) {
              row.blocks.push({
                id: `${message.id}-tool-result-${blockIndex}`,
                kind: "error",
                message: outputText,
              });
            } else {
              row.blocks.push({
                id: `${message.id}-tool-result-${blockIndex}`,
                kind: "text",
                text: outputText,
              });
            }
          }
        });
      }

      if (row.blocks.length > 0) {
        rows.push(row);
      }
      continue;
    }

    if (messageType === "result") {
      const isError = Boolean(payload.is_error);
      if (!isError) {
        continue;
      }
      const messageText =
        sanitizeText(readString(payload.content)) ??
        sanitizeText(readString(payload.result)) ??
        "The agent reported an error.";
      rows.push({
        blocks: [
          {
            id: `${message.id}-error`,
            kind: "error",
            message: messageText,
          },
        ],
        id: message.id,
        messageId: message.id,
        role: "system",
        sequenceNumber: normalizeSequenceNumber(message.sequence_number),
      });
    }
  }

  return rows.filter((row) => row.blocks.length > 0);
}

function registerAnchorsForRow(
  rows: ConversationRow[],
  rowIndex: number,
  toolAnchors: Map<string, ToolAnchor>,
  subAgentAnchors: Map<string, BlockAnchor>,
  todoAnchors: Map<string, BlockAnchor>
) {
  const row = rows[rowIndex];
  row.blocks.forEach((block, blockIndex) => {
    if (block.kind === "tool" && block.tool.toolUseId) {
      toolAnchors.set(block.tool.toolUseId, {
        blockIndex,
        kind: "standalone",
        rowIndex,
      });
      return;
    }

    if (block.kind === "subagent") {
      subAgentAnchors.set(block.activity.parentToolUseId, {
        blockIndex,
        rowIndex,
      });
      block.activity.tools.forEach((tool, toolIndex) => {
        if (tool.toolUseId) {
          toolAnchors.set(tool.toolUseId, {
            blockIndex,
            kind: "subagent",
            rowIndex,
            toolIndex,
          });
        }
      });
      return;
    }

    if (block.kind === "todo") {
      const mergeKey = todoListMergeKey(block.todoList);
      if (mergeKey) {
        todoAnchors.set(mergeKey, {
          blockIndex,
          rowIndex,
        });
      }
    }
  });
}

function appendToolToSubAgent(
  rows: ConversationRow[],
  anchor: BlockAnchor,
  tool: ConversationTool,
  toolAnchors: Map<string, ToolAnchor>
) {
  const row = rows[anchor.rowIndex];
  const block = row?.blocks[anchor.blockIndex];
  if (!(row && block) || block.kind !== "subagent") {
    return;
  }
  const nextTools = mergeTools(block.activity.tools, [tool]);
  const nextActivity: ConversationSubAgent = {
    ...block.activity,
    status: deriveSubAgentStatus(nextTools, block.activity.status),
    tools: nextTools,
  };
  row.blocks[anchor.blockIndex] = {
    activity: nextActivity,
    id: block.id,
    kind: "subagent",
  };

  if (tool.toolUseId) {
    const toolIndex = nextTools.findIndex(
      (entry) => entry.toolUseId === tool.toolUseId
    );
    if (toolIndex >= 0) {
      toolAnchors.set(tool.toolUseId, {
        blockIndex: anchor.blockIndex,
        kind: "subagent",
        rowIndex: anchor.rowIndex,
        toolIndex,
      });
    }
  }
}

function updateToolAtAnchor(
  rows: ConversationRow[],
  anchor: ToolAnchor | null,
  update: (tool: ConversationTool) => ConversationTool
) {
  if (!anchor) {
    return false;
  }

  const row = rows[anchor.rowIndex];
  const block = row?.blocks[anchor.blockIndex];
  if (!(row && block)) {
    return false;
  }

  if (anchor.kind === "standalone" && block.kind === "tool") {
    row.blocks[anchor.blockIndex] = {
      id: block.id,
      kind: "tool",
      tool: update(block.tool),
    };
    return true;
  }

  if (anchor.kind === "subagent" && block.kind === "subagent") {
    const nextTools = block.activity.tools.slice();
    if (!nextTools[anchor.toolIndex]) {
      return false;
    }
    nextTools[anchor.toolIndex] = update(nextTools[anchor.toolIndex]);
    row.blocks[anchor.blockIndex] = {
      activity: {
        ...block.activity,
        status: deriveSubAgentStatus(nextTools, block.activity.status),
        tools: nextTools,
      },
      id: block.id,
      kind: "subagent",
    };
    return true;
  }

  return false;
}

function updateTodoAtAnchor(
  rows: ConversationRow[],
  anchor: BlockAnchor | null,
  todoList: ConversationTodoList
) {
  if (!anchor) {
    return;
  }
  const row = rows[anchor.rowIndex];
  const block = row?.blocks[anchor.blockIndex];
  if (!(row && block) || block.kind !== "todo") {
    return;
  }
  row.blocks[anchor.blockIndex] = {
    id: block.id,
    kind: "todo",
    todoList: {
      ...block.todoList,
      items: todoList.items,
    },
  };
}

function createConversationTool(
  toolName: string,
  toolUseId: string | null,
  parentToolUseId: string | null,
  inputValue: unknown,
  fallbackId: string
): ConversationTool {
  const input = stringifyValue(inputValue);
  const output = null;
  const preview = summarizeToolInput(inputValue);

  return {
    detail: input,
    id: toolUseId ?? fallbackId,
    input,
    output,
    parentToolUseId,
    preview,
    status: "running",
    toolName,
    toolUseId,
  };
}

function createSubAgentActivity(
  inputValue: unknown,
  fallbackId: string,
  parentToolUseId: string
): ConversationSubAgent {
  const input = coerceRecord(inputValue);
  return {
    description: readString(input?.description) ?? "",
    id: fallbackId,
    parentToolUseId,
    result: null,
    status: "running",
    subagentType: readString(input?.subagent_type) ?? "general-purpose",
    tools: [],
  };
}

function parseQuestionBlocks(
  inputValue: unknown,
  idPrefix: string
): ConversationBlock[] {
  const input = coerceRecord(inputValue);
  const rawQuestions = Array.isArray(input?.questions)
    ? input.questions
    : typeof input?.question === "string" && input.question.trim()
      ? [
          {
            header: input.header,
            options: input.options,
            question: input.question,
          },
        ]
      : [];

  return rawQuestions
    .map((value, index) => parseQuestion(value, `${idPrefix}-${index}`))
    .filter((question): question is ConversationQuestion => question !== null)
    .map((question) => ({
      id: question.id,
      kind: "question" as const,
      question,
    }));
}

function parseQuestionBlocksFromPayload(
  payload: Record<string, unknown>,
  messageId: string
) {
  const toolName =
    readString(payload.name) ?? readString(payload.tool_name) ?? null;
  if (!(toolName && isQuestionTool(toolName))) {
    return [];
  }
  return parseQuestionBlocks(
    payload.input ?? payload.args ?? payload.arguments,
    messageId
  );
}

function parseQuestion(
  value: unknown,
  fallbackId: string
): ConversationQuestion | null {
  const record = coerceRecord(value);
  const question =
    sanitizeText(readString(record?.question)) ??
    sanitizeText(readString(record?.prompt));
  if (!(record && question)) {
    return null;
  }

  const options = readArray(record.options)
    .map((entry) => parseQuestionOption(entry))
    .filter((entry): entry is ConversationQuestionOption => entry !== null);

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

function parseQuestionOption(
  value: unknown
): ConversationQuestionOption | null {
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
  if (!(record && label)) {
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

function parseTodoList(
  inputValue: unknown,
  fallbackId: string,
  toolUseId: string | null,
  parentToolUseId: string | null
): ConversationTodoList | null {
  const input = coerceRecord(inputValue);
  const directTodos = readArray(input?.todos);
  const nestedTodos = readArray(coerceRecord(input?.input)?.todos);
  const todos = directTodos.length > 0 ? directTodos : nestedTodos;
  const items = todos
    .map((entry, index) => parseTodoItem(entry, `${fallbackId}-${index}`))
    .filter((entry): entry is ConversationTodoItem => entry !== null);

  if (items.length === 0) {
    return null;
  }

  return {
    id: fallbackId,
    items,
    parentToolUseId,
    sourceToolUseId: toolUseId,
  };
}

function parseTodoItem(
  value: unknown,
  fallbackId: string
): ConversationTodoItem | null {
  const record = coerceRecord(value);
  const content =
    sanitizeText(readString(record?.content)) ??
    sanitizeText(readString(record?.text));
  if (!(record && content)) {
    return null;
  }

  const rawStatus = readString(record.status)?.toLowerCase();
  const status: ConversationTodoStatus =
    rawStatus === "completed"
      ? "completed"
      : rawStatus === "in_progress"
        ? "in_progress"
        : "pending";

  return {
    content,
    id: sanitizeText(readString(record.id)) ?? fallbackId,
    status,
  };
}

function collectToolResultText(block: Record<string, unknown>) {
  const content = block.content;
  if (typeof content === "string") {
    const text = sanitizeText(content);
    return text && !looksLikeProtocolArtifact(text) ? text : null;
  }

  if (Array.isArray(content)) {
    const fragments = content
      .map((entry) => sanitizeText(readString(readRecord(entry)?.text)))
      .filter((entry): entry is string => Boolean(entry))
      .filter((entry) => !looksLikeProtocolArtifact(entry));
    return fragments.join("\n\n").trim() || null;
  }

  return sanitizeText(stringifyValue(content));
}

function deriveSubAgentStatus(
  tools: ConversationTool[],
  fallback: ConversationToolStatus
): ConversationToolStatus {
  if (tools.some((tool) => tool.status === "failed")) {
    return "failed";
  }
  if (tools.length > 0 && tools.every((tool) => tool.status === "completed")) {
    return "completed";
  }
  if (tools.some((tool) => tool.status === "running")) {
    return "running";
  }
  return fallback;
}

function mergeTools(
  existing: ConversationTool[],
  incoming: ConversationTool[]
): ConversationTool[] {
  if (incoming.length === 0) {
    return existing.slice();
  }

  const merged = existing.slice();
  const indexByKey = new Map<string, number>();
  merged.forEach((tool, index) => {
    indexByKey.set(toolMergeKey(tool), index);
  });

  for (const tool of incoming) {
    const key = toolMergeKey(tool);
    const existingIndex = indexByKey.get(key);
    if (existingIndex == null) {
      indexByKey.set(key, merged.length);
      merged.push(tool);
      continue;
    }
    merged[existingIndex] = tool;
  }

  return merged;
}

function toolMergeKey(tool: ConversationTool) {
  return tool.toolUseId
    ? `tool:${tool.toolUseId}`
    : `tool:${tool.parentToolUseId ?? ""}:${tool.toolName}:${tool.input ?? ""}`;
}

function todoListMergeKey(todoList: ConversationTodoList) {
  return todoList.sourceToolUseId ?? todoList.parentToolUseId ?? null;
}

function isQuestionTool(toolName: string) {
  return (
    toolName === "AskUserQuestion" ||
    toolName === "ask_user_question" ||
    toolName === "request_user_input"
  );
}

function summarizeToolInput(value: unknown) {
  const record = coerceRecord(value);
  if (!record) {
    return sanitizeText(stringifyValue(value));
  }

  return (
    sanitizeText(readString(record.file_path)) ??
    sanitizeText(readString(record.pattern)) ??
    sanitizeText(readString(record.command_description)) ??
    sanitizeText(readString(record.description)) ??
    sanitizeText(readString(record.command)) ??
    sanitizeText(readString(record.query)) ??
    sanitizeText(readString(record.url)) ??
    sanitizeText(readString(record.prompt)) ??
    sanitizeText(readString(record.path)) ??
    null
  );
}

function looksLikeProtocolArtifact(text: string) {
  const trimmed = text.trim();
  if (!(trimmed.startsWith("{") && trimmed.endsWith("}"))) {
    return false;
  }

  const parsed = parseJsonValue(trimmed);
  const type = readString(readRecord(parsed)?.type)?.toLowerCase();
  return (
    type === "assistant" ||
    type === "result" ||
    type === "system" ||
    type === "tool_result" ||
    type === "user"
  );
}

function normalizePayload(value: unknown): NormalizedPayload {
  if (typeof value === "string") {
    const parsed = parseJsonValue(value);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return {
        kind: "object",
        value: parsed as Record<string, unknown>,
      };
    }
    return {
      kind: "text",
      value,
    };
  }

  if (value && typeof value === "object" && !Array.isArray(value)) {
    return {
      kind: "object",
      value: value as Record<string, unknown>,
    };
  }

  return {
    kind: "text",
    value: String(value ?? ""),
  };
}

function resolvePayload(payload: Record<string, unknown>) {
  let current = payload;
  let depth = 0;
  while (depth < 4) {
    const rawJson = readString(current.raw_json);
    const parsed = parseJsonValue(rawJson);
    const record = readRecord(parsed);
    if (!(rawJson && record)) {
      break;
    }
    current = record;
    depth += 1;
  }
  return current;
}

function parseJsonValue(value: string | null | undefined) {
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as unknown;
  } catch {
    return null;
  }
}

function stringifyValue(value: unknown) {
  if (value == null) {
    return null;
  }
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? trimmed : null;
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function sanitizeText(value: string | null | undefined) {
  if (!value) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function normalizeSequenceNumber(value: number | string | null | undefined) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return 0;
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

function coerceRecord(value: unknown) {
  if (typeof value === "string") {
    return readRecord(parseJsonValue(value));
  }
  return readRecord(value);
}
