/**
 * Multi-Device Session Manager
 *
 * Manages sessions with multiple participants where the host (executor)
 * broadcasts encrypted output to all viewers.
 */

import {
  computePairwiseSecret,
  deriveSessionKeyFromPair,
  encrypt,
  fromBase64,
  generateSessionKey,
  toBase64,
} from "@unbound/crypto";
import type {
  AddParticipantOptions,
  BroadcastResult,
  CreateSessionOptions,
  EncryptedParticipantMessage,
  MultiDeviceSession,
  SessionParticipant,
} from "./types.js";

/**
 * Default session duration (1 hour)
 */
const DEFAULT_SESSION_DURATION = 60 * 60 * 1000;

/**
 * Options for MultiDeviceSessionManager
 */
export interface SessionManagerOptions {
  /** Host device ID */
  hostDeviceId: string;
  /** Host device's private key for pairwise secret computation */
  hostPrivateKey: Uint8Array;
  /** Host device's public key */
  hostPublicKey: Uint8Array;
}

/**
 * Manages multi-device sessions with encrypted fan-out broadcasting
 */
export class MultiDeviceSessionManager {
  private sessions: Map<string, MultiDeviceSession> = new Map();
  private hostPrivateKey: Uint8Array;
  private hostPublicKey: Uint8Array;
  private hostDeviceId: string;

  constructor(options: SessionManagerOptions) {
    this.hostPrivateKey = options.hostPrivateKey;
    this.hostPublicKey = options.hostPublicKey;
    this.hostDeviceId = options.hostDeviceId;
  }

  /**
   * Create a new multi-device session
   */
  createSession(options: CreateSessionOptions): MultiDeviceSession {
    const sessionId = options.sessionId ?? crypto.randomUUID();
    const now = new Date();
    const durationMs = options.durationMs ?? DEFAULT_SESSION_DURATION;

    // Create host participant
    const hostParticipant: SessionParticipant = {
      deviceId: options.hostDeviceId,
      devicePublicKey: options.hostPublicKey,
      role: "host",
      permission: "full_control",
      joinedAt: now,
      isActive: true,
    };

    const session: MultiDeviceSession = {
      id: sessionId,
      hostDeviceId: options.hostDeviceId,
      state: "active",
      participants: new Map([[options.hostDeviceId, hostParticipant]]),
      createdAt: now,
      expiresAt: new Date(now.getTime() + durationMs),
      metadata: options.metadata,
    };

    this.sessions.set(sessionId, session);
    return session;
  }

  /**
   * Add a participant to a session
   */
  addParticipant(
    sessionId: string,
    options: AddParticipantOptions
  ): SessionParticipant {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    if (session.state !== "active") {
      throw new Error(`Session is not active: ${session.state}`);
    }

    // Compute pairwise secret with the participant
    const participantPublicKey = fromBase64(options.devicePublicKey);
    const pairwiseSecret = computePairwiseSecret(
      this.hostPrivateKey,
      participantPublicKey
    );

    // Derive session-specific key for this participant
    const sessionKey = deriveSessionKeyFromPair(
      pairwiseSecret.secret,
      sessionId
    );

    const participant: SessionParticipant = {
      deviceId: options.deviceId,
      devicePublicKey: options.devicePublicKey,
      role: options.role,
      permission: options.permission ?? "view_only",
      sessionKey,
      joinedAt: new Date(),
      isActive: true,
    };

    session.participants.set(options.deviceId, participant);
    return participant;
  }

  /**
   * Remove a participant from a session
   */
  removeParticipant(sessionId: string, deviceId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    const participant = session.participants.get(deviceId);
    if (!participant) {
      return false;
    }

    // Clear the session key from memory
    if (participant.sessionKey) {
      participant.sessionKey.fill(0);
    }

    return session.participants.delete(deviceId);
  }

  /**
   * Mark a participant as inactive (left but can rejoin)
   */
  setParticipantInactive(sessionId: string, deviceId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    const participant = session.participants.get(deviceId);
    if (!participant) {
      return false;
    }

    participant.isActive = false;
    return true;
  }

  /**
   * Encrypt a message for a specific participant
   */
  encryptForParticipant(
    sessionId: string,
    deviceId: string,
    plaintext: Uint8Array
  ): EncryptedParticipantMessage {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    const participant = session.participants.get(deviceId);
    if (!participant) {
      throw new Error(`Participant not found: ${deviceId}`);
    }

    if (!participant.sessionKey) {
      throw new Error(`No session key for participant: ${deviceId}`);
    }

    const { nonce, ciphertext } = encrypt(participant.sessionKey, plaintext);

    return {
      targetDeviceId: deviceId,
      payload: toBase64(ciphertext),
      nonce: toBase64(nonce),
    };
  }

  /**
   * Broadcast a message to all active participants (except host)
   */
  broadcastToParticipants(
    sessionId: string,
    plaintext: Uint8Array
  ): BroadcastResult {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session not found: ${sessionId}`);
    }

    const messages = new Map<string, EncryptedParticipantMessage>();
    const failed: string[] = [];

    for (const [deviceId, participant] of session.participants) {
      // Skip host and inactive participants
      if (deviceId === session.hostDeviceId || !participant.isActive) {
        continue;
      }

      try {
        const encrypted = this.encryptForParticipant(
          sessionId,
          deviceId,
          plaintext
        );
        messages.set(deviceId, encrypted);
      } catch {
        failed.push(deviceId);
      }
    }

    return { sessionId, messages, failed };
  }

  /**
   * Get a session by ID
   */
  getSession(sessionId: string): MultiDeviceSession | undefined {
    return this.sessions.get(sessionId);
  }

  /**
   * Get all active participants in a session
   */
  getActiveParticipants(sessionId: string): SessionParticipant[] {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return [];
    }

    return Array.from(session.participants.values()).filter((p) => p.isActive);
  }

  /**
   * Get participant count for a session
   */
  getParticipantCount(sessionId: string): number {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return 0;
    }
    return session.participants.size;
  }

  /**
   * Pause a session
   */
  pauseSession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session || session.state !== "active") {
      return false;
    }
    session.state = "paused";
    return true;
  }

  /**
   * Resume a paused session
   */
  resumeSession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session || session.state !== "paused") {
      return false;
    }
    session.state = "active";
    return true;
  }

  /**
   * End a session and clean up
   */
  endSession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }

    // Clear all session keys
    for (const participant of session.participants.values()) {
      if (participant.sessionKey) {
        participant.sessionKey.fill(0);
      }
    }

    session.state = "ended";
    session.participants.clear();
    return this.sessions.delete(sessionId);
  }

  /**
   * Check if a session has expired
   */
  isSessionExpired(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return true;
    }
    if (!session.expiresAt) {
      return false;
    }
    return new Date() > session.expiresAt;
  }

  /**
   * Clean up expired sessions
   */
  cleanupExpiredSessions(): number {
    let cleaned = 0;
    for (const [sessionId, session] of this.sessions) {
      if (session.expiresAt && new Date() > session.expiresAt) {
        this.endSession(sessionId);
        cleaned++;
      }
    }
    return cleaned;
  }

  /**
   * Get all active sessions
   */
  getActiveSessions(): MultiDeviceSession[] {
    return Array.from(this.sessions.values()).filter(
      (s) => s.state === "active"
    );
  }

  /**
   * Clear all sessions
   */
  clear(): void {
    for (const sessionId of this.sessions.keys()) {
      this.endSession(sessionId);
    }
  }
}

/**
 * Create a multi-device session manager
 */
export function createSessionManager(
  options: SessionManagerOptions
): MultiDeviceSessionManager {
  return new MultiDeviceSessionManager(options);
}

/**
 * Generate a random session key for web sessions
 * (Web sessions use random keys, not derived from pairwise secrets)
 */
export function generateWebSessionKey(): Uint8Array {
  return generateSessionKey();
}
