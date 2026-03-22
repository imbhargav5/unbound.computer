import { describe, expect, it } from "vitest";

import claudeParserFixtures from "../../../shared/ClaudeConversationTimeline/Fixtures/claude-parser-contract-fixtures.json";
import { buildConversationTimeline } from "./conversationTimeline";

import {
  buildSessionConversationTimeline,
  deriveLatestSessionCompletionSummary,
  sessionConversationBlockSemanticType,
} from "./sessionConversation";
import type { SessionMessage } from "./types";

describe("buildSessionConversationTimeline", () => {
  it("matches the Claude parser contract fixtures at a high level", () => {
    for (const testCase of claudeParserFixtures.cases) {
      const rows = buildSessionConversationTimeline(
        fixtureMessages(testCase.events),
        "claude"
      );

      if (typeof testCase.expect.entryCount === "number") {
        expect(rows.length, testCase.id).toBe(testCase.expect.entryCount);
      }

      if (Array.isArray(testCase.expect.roles)) {
        expect(uniqueRoles(rows), testCase.id).toEqual(testCase.expect.roles);
      }

      if (Array.isArray(testCase.expect.blockTypes)) {
        expect(uniqueSemanticBlockTypes(rows), testCase.id).toEqual(
          testCase.expect.blockTypes
        );
      }
    }
  });

  it("builds structured Codex rows without raw JSON", () => {
    const rows = buildSessionConversationTimeline(
      [
        message("1", 1, {
          type: "thread.started",
          thread_id: "thread_123",
        }),
        message("2", 2, {
          type: "item.completed",
          item: {
            type: "agent_message",
            text: "I checked the README and the diff is clean.",
          },
        }),
        message("3", 3, {
          type: "item.completed",
          item: {
            type: "command_execution",
            command: "/bin/zsh -lc pwd",
            aggregated_output: "/tmp/project\n",
            exit_code: 0,
            status: "completed",
          },
        }),
        message("4", 4, {
          type: "stderr",
          message: 'Auth(TokenRefreshFailed("invalid_grant"))',
        }),
      ],
      "codex"
    );

    expect(rows).toHaveLength(4);
    expect(flattenSemanticBlockTypes(rows)).toEqual([
      "note",
      "text",
      "command",
      "note",
    ]);
    expect(rows[1]?.blocks[0]).toMatchObject({
      kind: "text",
      text: "I checked the README and the diff is clean.",
    });
    expect(rows[2]?.blocks[0]).toMatchObject({
      command: "/bin/zsh -lc pwd",
      kind: "command",
      output: "/tmp/project",
    });
  });

  it("extracts Codex request_user_input prompts into question blocks", () => {
    const rows = buildSessionConversationTimeline(
      [
        message("1", 1, {
          type: "item.completed",
          item: {
            type: "agent_message",
            text: "I need a decision from the board.",
          },
          tool_name: "request_user_input",
          input: {
            questions: [
              {
                header: "Ship it",
                options: [
                  { label: "Proceed", value: "proceed" },
                  { label: "Pause", value: "pause" },
                ],
                question: "Should I continue?",
              },
            ],
          },
        }),
      ],
      "codex"
    );

    expect(flattenSemanticBlockTypes(rows)).toEqual(["question", "text"]);
    const questionBlock = rows[0]?.blocks[0];
    expect(questionBlock).toMatchObject({
      kind: "question",
      question: {
        header: "Ship it",
        question: "Should I continue?",
      },
    });
  });

  it("hides legacy daemon-injected run prompts and issue seed text from Claude rows", () => {
    const rows = buildSessionConversationTimeline(
      [
        message("seed", 1, syntheticIssueSeedText()),
        message("prompt", 2, syntheticRunPromptText()),
        message("user", 3, "how are you mate"),
      ],
      "claude"
    );

    expect(rows).toHaveLength(1);
    expect(rows[0]?.role).toBe("user");
    expect(rows[0]?.blocks[0]).toMatchObject({
      kind: "text",
      text: "how are you mate",
    });
  });

  it("keeps a plain issue-title seed visible in Claude rows", () => {
    const rows = buildSessionConversationTimeline(
      [
        message("title", 1, "how are you mate"),
        message("user", 2, {
          type: "assistant",
          message: {
            content: [{ type: "text", text: "Doing well." }],
          },
        }),
      ],
      "claude"
    );

    expect(rows).toHaveLength(2);
    expect(rows[0]?.role).toBe("user");
    expect(rows[0]?.blocks[0]).toMatchObject({
      kind: "text",
      text: "how are you mate",
    });
  });

  it("hides legacy daemon-injected run prompts from Codex rows", () => {
    const rows = buildSessionConversationTimeline(
      [
        message("prompt", 1, syntheticRunPromptText()),
        message("user", 2, "how are you mate"),
      ],
      "codex"
    );

    expect(rows).toHaveLength(1);
    expect(rows[0]?.blocks[0]).toMatchObject({
      kind: "text",
      text: "how are you mate",
    });
  });

  it("derives the latest Claude completion summary", () => {
    const summary = deriveLatestSessionCompletionSummary(
      [
        message("1", 1, {
          type: "result",
          result: "Implemented the requested README update.",
          stop_reason: "end_turn",
          total_cost_usd: 0.021,
          num_turns: 2,
          usage: {
            cache_creation_input_tokens: 80,
            cache_read_input_tokens: 120,
            input_tokens: 700,
            output_tokens: 310,
          },
        }),
      ],
      "claude"
    );

    expect(summary).toEqual({
      durationMs: null,
      outcomeLabel: "end_turn",
      summaryText: "Implemented the requested README update.",
      totalCostUSD: 0.021,
      totalTokens: 1210,
      turns: 2,
    });
  });

  it("derives the latest Codex completion summary", () => {
    const summary = deriveLatestSessionCompletionSummary(
      [
        message("1", 1, {
          type: "turn.completed",
          duration_ms: 8421,
          turn_count: 1,
          usage: {
            cached_input_tokens: 50,
            input_tokens: 300,
            output_tokens: 120,
          },
        }),
      ],
      "codex"
    );

    expect(summary).toEqual({
      durationMs: 8421,
      outcomeLabel: "turn_completed",
      summaryText: null,
      totalCostUSD: null,
      totalTokens: 470,
      turns: 1,
    });
  });
});

describe("buildConversationTimeline", () => {
  it("skips legacy daemon-injected bootstrap messages", () => {
    const rows = buildConversationTimeline([
      message("seed", 1, syntheticIssueSeedText()),
      message("prompt", 2, syntheticRunPromptText()),
      message("user", 3, "how are you mate"),
    ]);

    expect(rows).toHaveLength(1);
    expect(rows[0]?.role).toBe("user");
    expect(rows[0]?.blocks[0]).toMatchObject({
      kind: "text",
      text: "how are you mate",
    });
  });

  it("keeps a plain issue-title seed visible", () => {
    const rows = buildConversationTimeline([message("title", 1, "how are you mate")]);

    expect(rows).toHaveLength(1);
    expect(rows[0]?.role).toBe("user");
    expect(rows[0]?.blocks[0]).toMatchObject({
      kind: "text",
      text: "how are you mate",
    });
  });
});

function flattenSemanticBlockTypes(
  rows: ReturnType<typeof buildSessionConversationTimeline>
) {
  return rows.flatMap((row) =>
    row.blocks.map((block) => sessionConversationBlockSemanticType(block))
  );
}

function uniqueSemanticBlockTypes(
  rows: ReturnType<typeof buildSessionConversationTimeline>
) {
  return Array.from(new Set(flattenSemanticBlockTypes(rows)));
}

function uniqueRoles(
  rows: ReturnType<typeof buildSessionConversationTimeline>
) {
  return Array.from(new Set(rows.map((row) => row.role)));
}

function fixtureMessages(events: Array<Record<string, unknown>>) {
  return events.map((event, index) =>
    message(
      `fixture-${index + 1}`,
      index + 1,
      Object.hasOwn(event, "raw_json") ? event.raw_json : event
    )
  );
}

function message(
  id: string,
  sequenceNumber: number,
  content: unknown
): SessionMessage {
  return {
    content: typeof content === "string" ? content : JSON.stringify(content),
    id,
    sequence_number: sequenceNumber,
    session_id: "session-1",
  };
}

function syntheticIssueSeedText() {
  return [
    "Conversation: ISSUE-1",
    "Title: Hello",
    "Description: Seeded issue context",
    "Status: todo",
    "Priority: medium",
  ].join("\n");
}

function syntheticRunPromptText() {
  return [
    "Conversation: ISSUE-1",
    "Title: Hello",
    "Description: Seeded issue context",
    "Status: todo",
    "Priority: medium",
    "",
    "You are Builder, a engineer agent inside Unbound.",
    "",
    "This run is focused on issue issue-1. Read the issue context and do the next useful piece of work.",
    "",
    "Governance rules:",
    "- Hiring must use the board helper commands below.",
    "",
    "Board helper commands:",
    "- Prepare the issue worktree: \"unbound-daemon\" --base-dir \"/tmp\" board issue-checkout --issue-id \"issue-1\"",
    "",
    "Issue: ISSUE-1",
  ].join("\n");
}
