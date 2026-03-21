import { describe, expect, it } from "vitest";

import claudeParserFixtures from "../../../shared/ClaudeConversationTimeline/Fixtures/claude-parser-contract-fixtures.json";

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
        expect(
          uniqueRoles(rows),
          testCase.id
        ).toEqual(testCase.expect.roles);
      }

      if (Array.isArray(testCase.expect.blockTypes)) {
        expect(
          uniqueSemanticBlockTypes(rows),
          testCase.id
        ).toEqual(testCase.expect.blockTypes);
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
          message: "Auth(TokenRefreshFailed(\"invalid_grant\"))",
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

function uniqueRoles(rows: ReturnType<typeof buildSessionConversationTimeline>) {
  return Array.from(new Set(rows.map((row) => row.role)));
}

function fixtureMessages(events: Array<Record<string, unknown>>) {
  return events.map((event, index) =>
    message(
      `fixture-${index + 1}`,
      index + 1,
      Object.prototype.hasOwnProperty.call(event, "raw_json")
        ? event.raw_json
        : event
    )
  );
}

function message(
  id: string,
  sequenceNumber: number,
  content: unknown
): SessionMessage {
  return {
    content:
      typeof content === "string" ? content : JSON.stringify(content),
    id,
    sequence_number: sequenceNumber,
    session_id: "session-1",
  };
}
