import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { DesktopSessionStateManager } from "./sessionLiveState";
import type { SessionMessage } from "./types";

describe("DesktopSessionStateManager", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("activates a session and hydrates cached conversation state", async () => {
    const api = createMockApi([
      [
        message("1", 1, "ship this"),
        message("2", 2, {
          type: "assistant",
          message: {
            content: [{ type: "text", text: "Working on it" }],
          },
        }),
        message("3", 3, {
          type: "result",
          result: "Completed successfully.",
          total_cost_usd: 0.01,
          usage: {
            input_tokens: 100,
            output_tokens: 40,
          },
        }),
      ],
    ]);
    const manager = new DesktopSessionStateManager(api);
    const state = manager.stateFor("session-1", "claude");

    state.activate("claude");
    await flushAsync();

    const snapshot = state.getSnapshot();
    expect(snapshot.subscriptionState).toBe("subscribed");
    expect(snapshot.messages).toHaveLength(3);
    expect(snapshot.conversationRows).toHaveLength(3);
    expect(snapshot.latestCompletionSummary).toMatchObject({
      summaryText: "Completed successfully.",
      totalCostUSD: 0.01,
      totalTokens: 140,
    });
    expect(api.sessionSubscribe).toHaveBeenCalledWith("session-1");
  });

  it("refreshes the active session after daemon events", async () => {
    const api = createMockApi([
      [message("1", 1, "first")],
      [
        message("1", 1, "first"),
        message("2", 2, {
          type: "assistant",
          message: {
            content: [{ type: "text", text: "second" }],
          },
        }),
      ],
    ]);
    const manager = new DesktopSessionStateManager(api);
    const state = manager.stateFor("session-1", "claude");

    state.activate("claude");
    await flushAsync();

    manager.handleSessionEvent({
      event: {},
      session_id: "session-1",
    });
    await vi.runAllTimersAsync();
    await flushAsync();

    expect(state.getSnapshot().messages).toHaveLength(2);
    expect(api.messageList).toHaveBeenCalledTimes(2);
  });

  it("preserves cached rows across deactivate and re-activate", async () => {
    const api = createMockApi([[message("1", 1, "cached prompt")]]);
    const manager = new DesktopSessionStateManager(api);
    const state = manager.stateFor("session-1", "claude");

    state.activate("claude");
    await flushAsync();
    state.deactivate();
    await flushAsync();

    expect(state.getSnapshot().messages).toHaveLength(1);
    expect(state.getSnapshot().subscriptionState).toBe("idle");

    state.activate("claude");
    await flushAsync();

    expect(state.getSnapshot().messages).toHaveLength(1);
    expect(api.sessionSubscribe).toHaveBeenCalledTimes(2);
    expect(api.sessionUnsubscribe).toHaveBeenCalledTimes(1);
  });

  it("returns a stable empty snapshot for missing sessions", () => {
    const manager = new DesktopSessionStateManager(createMockApi([]));

    const first = manager.emptySnapshot(null, "claude");
    const second = manager.emptySnapshot(null, "claude");
    const third = manager.emptySnapshot(null, "codex");

    expect(second).toBe(first);
    expect(third).not.toBe(first);
    expect(first.sessionId).toBe("missing-session");
  });

  it("captures stream errors on the active session", async () => {
    const api = createMockApi([[message("1", 1, "hello")]]);
    const manager = new DesktopSessionStateManager(api);
    const state = manager.stateFor("session-1", "claude");

    state.activate("claude");
    await flushAsync();

    manager.handleStreamError({
      message: "socket dropped",
      session_id: "session-1",
    });

    expect(state.getSnapshot().errorMessage).toBe("socket dropped");
    expect(state.getSnapshot().subscriptionState).toBe("disconnected");
  });
});

function createMockApi(messageResponses: SessionMessage[][]) {
  let index = 0;

  return {
    agentStatus: vi.fn(async () => ({ status: "idle" })),
    messageList: vi.fn(async () => {
      const current =
        messageResponses[Math.min(index, messageResponses.length - 1)];
      index += 1;
      return current;
    }),
    sessionSubscribe: vi.fn(async () => undefined),
    sessionUnsubscribe: vi.fn(async () => undefined),
    terminalStatus: vi.fn(async () => ({ status: "idle" })),
  };
}

async function flushAsync() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
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
