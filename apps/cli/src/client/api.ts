import { config, endpoints } from "../config.js";
import { logger } from "../utils/index.js";

/**
 * Repository data structure
 */
export interface Repository {
  id: string;
  name: string;
  localPath: string;
  remoteUrl?: string;
  defaultBranch?: string;
  isWorktree: boolean;
  worktreeBranch?: string;
  parentRepositoryId?: string;
  status: "active" | "archived";
  lastSyncedAt?: string;
}

/**
 * Coding session data structure
 */
export interface CodingSession {
  id: string;
  repositoryId: string;
  deviceId: string;
  sessionPid?: number;
  status: "active" | "paused" | "ended";
  currentBranch?: string;
  workingDirectory?: string;
  sessionStartedAt: string;
  sessionEndedAt?: string;
  lastHeartbeatAt?: string;
}

/**
 * API client for Unbound web API
 */
export class ApiClient {
  private apiKey: string;
  private deviceId: string;

  constructor(apiKey: string, deviceId: string) {
    this.apiKey = apiKey;
    this.deviceId = deviceId;
  }

  /**
   * Make an API request
   */
  private async request<T>(
    method: string,
    path: string,
    body?: unknown
  ): Promise<T> {
    const url = `${config.apiUrl}${path}`;

    logger.debug(`API ${method} ${path}`);

    const response = await fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(config.apiTimeout),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`API error ${response.status}: ${errorText}`);
    }

    return response.json() as Promise<T>;
  }

  /**
   * Register a repository
   */
  async registerRepository(data: {
    name: string;
    localPath: string;
    remoteUrl?: string;
    defaultBranch?: string;
    isWorktree: boolean;
    worktreeBranch?: string;
    parentRepositoryId?: string;
  }): Promise<Repository> {
    return this.request<Repository>("POST", endpoints.repositories, {
      deviceId: this.deviceId,
      ...data,
    });
  }

  /**
   * List repositories for this device
   */
  async listRepositories(): Promise<Repository[]> {
    const result = await this.request<{ repositories: Repository[] }>(
      "GET",
      `${endpoints.repositories}?deviceId=${this.deviceId}`
    );
    return result.repositories;
  }

  /**
   * Archive a repository (soft delete)
   */
  async archiveRepository(repositoryId: string): Promise<void> {
    await this.request("PATCH", `${endpoints.repositories}/${repositoryId}`, {
      status: "archived",
    });
  }

  /**
   * Create a coding session
   */
  async createSession(data: {
    repositoryId: string;
    sessionPid?: number;
    currentBranch?: string;
    workingDirectory?: string;
  }): Promise<CodingSession> {
    return this.request<CodingSession>("POST", endpoints.sessions, {
      deviceId: this.deviceId,
      ...data,
    });
  }

  /**
   * Update a coding session
   */
  async updateSession(
    sessionId: string,
    data: {
      status?: "active" | "paused" | "ended";
      currentBranch?: string;
      workingDirectory?: string;
    }
  ): Promise<CodingSession> {
    return this.request<CodingSession>(
      "PATCH",
      `${endpoints.sessions}/${sessionId}`,
      data
    );
  }

  /**
   * Send session heartbeat
   */
  async heartbeat(sessionId: string): Promise<void> {
    await this.request("PATCH", `${endpoints.sessions}/${sessionId}`, {
      lastHeartbeatAt: new Date().toISOString(),
    });
  }

  /**
   * End a coding session
   */
  async endSession(sessionId: string): Promise<void> {
    await this.request("PATCH", `${endpoints.sessions}/${sessionId}`, {
      status: "ended",
      sessionEndedAt: new Date().toISOString(),
    });
  }

  /**
   * List active sessions for this device
   */
  async listSessions(
    status?: "active" | "paused" | "ended"
  ): Promise<CodingSession[]> {
    let url = `${endpoints.sessions}?deviceId=${this.deviceId}`;
    if (status) {
      url += `&status=${status}`;
    }

    const result = await this.request<{ sessions: CodingSession[] }>(
      "GET",
      url
    );
    return result.sessions;
  }
}
