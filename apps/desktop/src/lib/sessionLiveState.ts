import { useCallback, useEffect, useMemo, useSyncExternalStore } from "react";

import {
  agentStatus,
  messageList,
  sessionSubscribe,
  sessionUnsubscribe,
  terminalStatus,
} from "./api";
import {
  buildSessionConversationTimeline,
  deriveLatestSessionCompletionSummary,
  type SessionCompletionSummary,
  type SessionConversationProvider,
  type SessionConversationRow,
} from "./sessionConversation";
import type { SessionMessage, SessionStreamPayload } from "./types";

export type DesktopSessionSubscriptionState =
  | "idle"
  | "connecting"
  | "subscribed"
  | "disconnected";

export interface DesktopSessionStateSnapshot {
  conversationRows: SessionConversationRow[];
  errorMessage: string | null;
  isLoadingMessages: boolean;
  latestCompletionSummary: SessionCompletionSummary | null;
  messages: SessionMessage[];
  provider: SessionConversationProvider;
  runtimeStatus: Record<string, unknown> | null;
  sessionId: string;
  subscriptionState: DesktopSessionSubscriptionState;
  terminalStatus: Record<string, unknown> | null;
}

export interface DesktopSessionLiveStateApi {
  agentStatus(sessionId: string): Promise<Record<string, unknown>>;
  messageList(sessionId: string): Promise<SessionMessage[]>;
  sessionSubscribe(sessionId: string): Promise<void>;
  sessionUnsubscribe(sessionId: string): Promise<void>;
  terminalStatus(sessionId: string): Promise<Record<string, unknown>>;
}

const emptySnapshotByKey = new Map<string, DesktopSessionStateSnapshot>();

function emptySnapshotKey(
  sessionId: string | null,
  provider: SessionConversationProvider
) {
  return `${sessionId ?? "missing-session"}:${provider}`;
}

function createEmptySnapshot(
  sessionId: string,
  provider: SessionConversationProvider
): DesktopSessionStateSnapshot {
  return {
    conversationRows: [],
    errorMessage: null,
    isLoadingMessages: false,
    latestCompletionSummary: null,
    messages: [],
    provider,
    runtimeStatus: null,
    sessionId,
    subscriptionState: "idle",
    terminalStatus: null,
  };
}

const defaultDesktopSessionLiveStateApi: DesktopSessionLiveStateApi = {
  agentStatus,
  messageList,
  sessionSubscribe,
  sessionUnsubscribe,
  terminalStatus,
};

class DesktopSessionLiveState {
  private activationCount = 0;
  private readonly api: DesktopSessionLiveStateApi;
  private readonly listeners = new Set<() => void>();
  private refreshGeneration = 0;
  private refreshTimeout: ReturnType<typeof setTimeout> | null = null;
  private snapshot: DesktopSessionStateSnapshot;

  constructor(
    private readonly sessionId: string,
    provider: SessionConversationProvider,
    api: DesktopSessionLiveStateApi
  ) {
    this.api = api;
    this.snapshot = createEmptySnapshot(sessionId, provider);
  }

  activate(provider: SessionConversationProvider) {
    this.activationCount += 1;
    this.setProvider(provider);
    if (
      this.snapshot.subscriptionState === "subscribed" ||
      this.snapshot.subscriptionState === "connecting"
    ) {
      return;
    }

    this.updateSnapshot({
      errorMessage: null,
      isLoadingMessages:
        this.snapshot.messages.length === 0 ||
        this.snapshot.errorMessage != null,
      subscriptionState: "connecting",
    });

    const generation = ++this.refreshGeneration;
    void Promise.all([
      this.refresh(generation),
      this.api.sessionSubscribe(this.sessionId),
    ])
      .then(() => {
        if (
          generation !== this.refreshGeneration ||
          this.activationCount === 0
        ) {
          return;
        }
        this.updateSnapshot({
          subscriptionState: "subscribed",
        });
      })
      .catch((error) => {
        if (generation !== this.refreshGeneration) {
          return;
        }
        this.updateSnapshot({
          errorMessage: error instanceof Error ? error.message : String(error),
          isLoadingMessages: false,
          subscriptionState: "disconnected",
        });
      });
  }

  deactivate() {
    this.activationCount = Math.max(0, this.activationCount - 1);
    if (this.activationCount > 0) {
      return;
    }

    this.clearRefreshTimeout();
    const generation = ++this.refreshGeneration;
    void this.api
      .sessionUnsubscribe(this.sessionId)
      .catch(() => null)
      .finally(() => {
        if (generation !== this.refreshGeneration) {
          return;
        }
        this.updateSnapshot({
          isLoadingMessages: false,
          subscriptionState: "idle",
        });
      });
  }

  getSnapshot = () => this.snapshot;

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  handleSessionEvent(payload: SessionStreamPayload) {
    if (payload.session_id !== this.sessionId || this.activationCount === 0) {
      return;
    }

    this.clearRefreshTimeout();
    this.refreshTimeout = setTimeout(() => {
      this.refreshTimeout = null;
      void this.refresh(++this.refreshGeneration);
    }, 120);
  }

  handleStreamError(message: string) {
    this.updateSnapshot({
      errorMessage: message,
      subscriptionState: "disconnected",
    });
  }

  private async refresh(generation: number) {
    this.updateSnapshot({
      errorMessage: null,
      isLoadingMessages: true,
    });

    try {
      const [messages, runtimeStatus, nextTerminalStatus] = await Promise.all([
        this.api.messageList(this.sessionId),
        this.api.agentStatus(this.sessionId),
        this.api.terminalStatus(this.sessionId),
      ]);
      if (generation !== this.refreshGeneration) {
        return;
      }

      const provider = this.snapshot.provider;
      this.updateSnapshot({
        conversationRows: buildSessionConversationTimeline(messages, provider),
        errorMessage: null,
        isLoadingMessages: false,
        latestCompletionSummary: deriveLatestSessionCompletionSummary(
          messages,
          provider
        ),
        messages,
        runtimeStatus,
        terminalStatus: nextTerminalStatus,
      });
    } catch (error) {
      if (generation !== this.refreshGeneration) {
        return;
      }

      this.updateSnapshot({
        errorMessage: error instanceof Error ? error.message : String(error),
        isLoadingMessages: false,
      });
    }
  }

  private clearRefreshTimeout() {
    if (this.refreshTimeout !== null) {
      clearTimeout(this.refreshTimeout);
      this.refreshTimeout = null;
    }
  }

  private setProvider(provider: SessionConversationProvider) {
    if (this.snapshot.provider === provider) {
      return;
    }

    this.updateSnapshot({
      conversationRows: buildSessionConversationTimeline(
        this.snapshot.messages,
        provider
      ),
      latestCompletionSummary: deriveLatestSessionCompletionSummary(
        this.snapshot.messages,
        provider
      ),
      provider,
    });
  }

  private updateSnapshot(patch: Partial<DesktopSessionStateSnapshot>) {
    this.snapshot = {
      ...this.snapshot,
      ...patch,
    };
    this.listeners.forEach((listener) => listener());
  }
}

export class DesktopSessionStateManager {
  private readonly api: DesktopSessionLiveStateApi;
  private readonly states = new Map<string, DesktopSessionLiveState>();

  constructor(
    api: DesktopSessionLiveStateApi = defaultDesktopSessionLiveStateApi
  ) {
    this.api = api;
  }

  stateFor(sessionId: string, provider: SessionConversationProvider) {
    const existing = this.states.get(sessionId);
    if (existing) {
      return existing;
    }

    const next = new DesktopSessionLiveState(sessionId, provider, this.api);
    this.states.set(sessionId, next);
    return next;
  }

  emptySnapshot(
    sessionId: string | null,
    provider: SessionConversationProvider
  ) {
    const key = emptySnapshotKey(sessionId, provider);
    const cached = emptySnapshotByKey.get(key);
    if (cached) {
      return cached;
    }

    const snapshot = createEmptySnapshot(
      sessionId ?? "missing-session",
      provider
    );
    emptySnapshotByKey.set(key, snapshot);
    return snapshot;
  }

  handleSessionEvent(payload: SessionStreamPayload) {
    this.states.get(payload.session_id)?.handleSessionEvent(payload);
  }

  handleStreamError(payload: { message: string; session_id: string }) {
    this.states.get(payload.session_id)?.handleStreamError(payload.message);
  }
}

export function useDesktopSessionLiveState(
  manager: DesktopSessionStateManager,
  sessionId: string | null,
  provider: SessionConversationProvider
) {
  const liveState = useMemo(
    () => (sessionId ? manager.stateFor(sessionId, provider) : null),
    [manager, provider, sessionId]
  );

  useEffect(() => {
    if (!liveState) {
      return;
    }

    liveState.activate(provider);
    return () => {
      liveState.deactivate();
    };
  }, [liveState, provider]);

  const emptySnapshot = useMemo(
    () => manager.emptySnapshot(sessionId, provider),
    [manager, provider, sessionId]
  );
  const getSnapshot = useCallback(
    () => liveState?.getSnapshot() ?? emptySnapshot,
    [emptySnapshot, liveState]
  );
  const subscribe = useMemo(
    () => liveState?.subscribe ?? noopSubscribe,
    [liveState]
  );

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

function noopSubscribe() {
  return () => undefined;
}
