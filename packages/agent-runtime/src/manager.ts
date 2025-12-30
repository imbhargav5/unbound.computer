import { EventEmitter } from "node:events";
import { createSession, type Session } from "./session.js";
import {
  DEFAULT_SESSION_MANAGER_CONFIG,
  type SessionConfig,
  type SessionManagerConfig,
  type SessionMetadata,
  type SessionResult,
  SessionState,
} from "./types.js";

/**
 * Session manager events
 */
export interface SessionManagerEvents {
  sessionCreated: [sessionId: string];
  sessionStarted: [sessionId: string];
  sessionEnded: [sessionId: string, state: SessionState];
  sessionError: [sessionId: string, error: Error];
  output: [sessionId: string, content: string];
}

/**
 * Session manager - handles multiple concurrent Claude Code sessions
 */
export class SessionManager extends EventEmitter {
  private config: SessionManagerConfig;
  private sessions: Map<string, Session> = new Map();
  private heartbeatInterval: NodeJS.Timeout | null = null;

  constructor(config: Partial<SessionManagerConfig> = {}) {
    super();
    this.config = { ...DEFAULT_SESSION_MANAGER_CONFIG, ...config };
  }

  /**
   * Get configuration
   */
  getConfig(): SessionManagerConfig {
    return { ...this.config };
  }

  /**
   * Create a new session
   */
  createSession(config: SessionConfig): SessionResult<Session> {
    // Check concurrent session limit
    const activeSessions = this.getActiveSessions();
    if (activeSessions.length >= this.config.maxConcurrentSessions) {
      return {
        success: false,
        error: `Maximum concurrent sessions (${this.config.maxConcurrentSessions}) reached`,
      };
    }

    // Check if session already exists
    if (this.sessions.has(config.sessionId)) {
      return {
        success: false,
        error: `Session already exists: ${config.sessionId}`,
      };
    }

    // Create session with configured timeout
    const sessionConfig: SessionConfig = {
      ...config,
      timeoutMs: config.timeoutMs ?? this.config.defaultTimeoutMs,
    };

    const session = createSession(
      sessionConfig,
      this.config.claudeCommand,
      this.config.claudeArgs
    );

    // Set up session event handlers
    this.setupSessionHandlers(session);

    // Store session
    this.sessions.set(config.sessionId, session);
    this.emit("sessionCreated", config.sessionId);

    return { success: true, data: session };
  }

  /**
   * Get a session by ID
   */
  getSession(sessionId: string): Session | undefined {
    return this.sessions.get(sessionId);
  }

  /**
   * Start a session
   */
  async startSession(sessionId: string): Promise<SessionResult<void>> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return {
        success: false,
        error: `Session not found: ${sessionId}`,
      };
    }

    const result = await session.start();
    if (result.success) {
      this.emit("sessionStarted", sessionId);
    }

    return result;
  }

  /**
   * Create and start a session
   */
  async createAndStartSession(
    config: SessionConfig
  ): Promise<SessionResult<Session>> {
    const createResult = this.createSession(config);
    if (!createResult.success) {
      return createResult;
    }

    const startResult = await this.startSession(config.sessionId);
    if (!startResult.success) {
      // Clean up on failure
      this.removeSession(config.sessionId);
      return {
        success: false,
        error: startResult.error,
      };
    }

    return createResult;
  }

  /**
   * Stop a session
   */
  async stopSession(sessionId: string): Promise<SessionResult<void>> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return {
        success: false,
        error: `Session not found: ${sessionId}`,
      };
    }

    return session.stop();
  }

  /**
   * Kill a session
   */
  killSession(sessionId: string): SessionResult<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return {
        success: false,
        error: `Session not found: ${sessionId}`,
      };
    }

    session.kill();
    return { success: true };
  }

  /**
   * Pause a session
   */
  pauseSession(sessionId: string): SessionResult<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return {
        success: false,
        error: `Session not found: ${sessionId}`,
      };
    }

    return session.pause();
  }

  /**
   * Resume a session
   */
  resumeSession(sessionId: string): SessionResult<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return {
        success: false,
        error: `Session not found: ${sessionId}`,
      };
    }

    return session.resume();
  }

  /**
   * Send input to a session
   */
  sendInput(sessionId: string, content: string): SessionResult<void> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return {
        success: false,
        error: `Session not found: ${sessionId}`,
      };
    }

    return session.sendInput(content);
  }

  /**
   * Remove a session
   */
  removeSession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    session.cleanup();
    return this.sessions.delete(sessionId);
  }

  /**
   * Get all sessions
   */
  getAllSessions(): Session[] {
    return Array.from(this.sessions.values());
  }

  /**
   * Get active sessions (running or paused)
   */
  getActiveSessions(): Session[] {
    return this.getAllSessions().filter((s) => s.isActive());
  }

  /**
   * Get session metadata for all sessions
   */
  getAllMetadata(): SessionMetadata[] {
    return this.getAllSessions().map((s) => s.getMetadata());
  }

  /**
   * Get statistics
   */
  getStats(): {
    total: number;
    active: number;
    running: number;
    paused: number;
    completed: number;
    error: number;
  } {
    const sessions = this.getAllSessions();
    const states = sessions.map((s) => s.getState());

    return {
      total: sessions.length,
      active: states.filter(
        (s) => s === SessionState.RUNNING || s === SessionState.PAUSED
      ).length,
      running: states.filter((s) => s === SessionState.RUNNING).length,
      paused: states.filter((s) => s === SessionState.PAUSED).length,
      completed: states.filter((s) => s === SessionState.COMPLETED).length,
      error: states.filter((s) => s === SessionState.ERROR).length,
    };
  }

  /**
   * Stop all sessions
   */
  async stopAll(): Promise<void> {
    const promises = this.getAllSessions().map((session) => session.stop());
    await Promise.all(promises);
  }

  /**
   * Kill all sessions
   */
  killAll(): void {
    for (const session of this.sessions.values()) {
      session.kill();
    }
  }

  /**
   * Clean up terminated sessions
   */
  cleanupTerminated(): number {
    let cleaned = 0;

    for (const [id, session] of this.sessions) {
      if (session.isTerminal()) {
        session.cleanup();
        this.sessions.delete(id);
        cleaned++;
      }
    }

    return cleaned;
  }

  /**
   * Start heartbeat monitoring
   */
  startHeartbeat(): void {
    if (this.heartbeatInterval) {
      return;
    }

    this.heartbeatInterval = setInterval(() => {
      // Clean up terminated sessions
      this.cleanupTerminated();
    }, this.config.heartbeatIntervalMs);
  }

  /**
   * Stop heartbeat monitoring
   */
  stopHeartbeat(): void {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  /**
   * Shutdown the manager
   */
  async shutdown(): Promise<void> {
    this.stopHeartbeat();
    await this.stopAll();
    this.sessions.clear();
  }

  /**
   * Set up session event handlers
   */
  private setupSessionHandlers(session: Session): void {
    const sessionId = session.getId();

    session.on("stateChange", ({ newState }) => {
      if (
        newState === SessionState.COMPLETED ||
        newState === SessionState.ERROR
      ) {
        this.emit("sessionEnded", sessionId, newState);
      }
    });

    session.on("output", (content) => {
      this.emit("output", sessionId, content);
    });

    session.on("error", (error) => {
      this.emit("sessionError", sessionId, error);
    });
  }

  // Type-safe event methods
  override on(
    event: "sessionCreated",
    listener: (sessionId: string) => void
  ): this;
  override on(
    event: "sessionStarted",
    listener: (sessionId: string) => void
  ): this;
  override on(
    event: "sessionEnded",
    listener: (sessionId: string, state: SessionState) => void
  ): this;
  override on(
    event: "sessionError",
    listener: (sessionId: string, error: Error) => void
  ): this;
  override on(
    event: "output",
    listener: (sessionId: string, content: string) => void
  ): this;
  // biome-ignore lint/suspicious/noExplicitAny: Required for EventEmitter overload compatibility
  override on(event: string, listener: (...args: any[]) => void): this {
    return super.on(event, listener);
  }
}

/**
 * Create a session manager
 */
export function createSessionManager(
  config?: Partial<SessionManagerConfig>
): SessionManager {
  return new SessionManager(config);
}
