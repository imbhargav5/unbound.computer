import {
  bytesToString,
  computePairwiseSecret,
  decrypt,
  deriveSessionKey,
  deriveSessionKeyFromPair,
  encrypt,
  fromBase64,
  stringToBytes,
  toBase64,
} from "@unbound/crypto";
import type { SessionMessage } from "./types.js";

/**
 * Encrypted message format
 */
export interface EncryptedSessionMessage {
  /** Message ID */
  id: string;
  /** Nonce used for encryption (base64) */
  nonce: string;
  /** Encrypted payload (base64) */
  payload: string;
  /** Sequence number */
  sequence: number;
  /** Session ID */
  sessionId: string;
  /** Timestamp */
  timestamp: number;
}

/**
 * Session encryption context
 * Handles encrypting/decrypting messages for a specific session
 * @deprecated Use PairwiseSessionEncryption for device-rooted trust model
 */
export class SessionEncryption {
  private sessionId: string;
  private sessionKey: Uint8Array;

  constructor(masterKey: Uint8Array, sessionId: string) {
    this.sessionId = sessionId;
    // Derive session key: SK = HKDF(MK, session_id)
    this.sessionKey = deriveSessionKey(masterKey, sessionId);
  }

  /**
   * Encrypt a message for transmission
   */
  encryptMessage(message: SessionMessage): EncryptedSessionMessage {
    // Serialize message content
    const plaintext = JSON.stringify({
      type: message.type,
      content: message.content,
    });

    // Convert to bytes and encrypt with session key
    const plaintextBytes = stringToBytes(plaintext);
    const encrypted = encrypt(this.sessionKey, plaintextBytes);

    return {
      id: message.id,
      sessionId: message.sessionId,
      payload: toBase64(encrypted.ciphertext),
      nonce: toBase64(encrypted.nonce),
      timestamp: message.timestamp.getTime(),
      sequence: message.sequence,
    };
  }

  /**
   * Decrypt a received message
   */
  decryptMessage(
    encrypted: EncryptedSessionMessage
  ): Pick<SessionMessage, "type" | "content"> {
    // Decode from base64
    const ciphertext = fromBase64(encrypted.payload);
    const nonce = fromBase64(encrypted.nonce);

    // Decrypt with session key
    const plaintextBytes = decrypt(this.sessionKey, nonce, ciphertext);
    const plaintext = bytesToString(plaintextBytes);

    // Parse message content
    const parsed = JSON.parse(plaintext) as {
      type: SessionMessage["type"];
      content: string;
    };

    return {
      type: parsed.type,
      content: parsed.content,
    };
  }

  /**
   * Encrypt arbitrary data
   */
  encrypt(data: string): { payload: string; nonce: string } {
    const dataBytes = stringToBytes(data);
    const encrypted = encrypt(this.sessionKey, dataBytes);
    return {
      payload: toBase64(encrypted.ciphertext),
      nonce: toBase64(encrypted.nonce),
    };
  }

  /**
   * Decrypt arbitrary data
   */
  decrypt(payload: string, nonce: string): string {
    const ciphertext = fromBase64(payload);
    const nonceBytes = fromBase64(nonce);
    const plaintextBytes = decrypt(this.sessionKey, nonceBytes, ciphertext);
    return bytesToString(plaintextBytes);
  }

  /**
   * Get session ID
   */
  getSessionId(): string {
    return this.sessionId;
  }

  /**
   * Clear the session key from memory
   */
  clear(): void {
    // Overwrite key with zeros
    this.sessionKey.fill(0);
  }
}

/**
 * Options for creating a pairwise session encryption context
 */
export interface PairwiseSessionEncryptionOptions {
  /** My device's private key */
  myPrivateKey: Uint8Array;
  /** Peer device's public key */
  peerPublicKey: Uint8Array;
  /** Session ID */
  sessionId: string;
}

/**
 * Pairwise session encryption context
 *
 * Uses X25519 ECDH to compute a pairwise secret, then derives
 * a session key using HKDF. This replaces the Master Key-based
 * approach where devices now own their own long-term keys.
 */
export class PairwiseSessionEncryption {
  private sessionId: string;
  private sessionKey: Uint8Array;

  constructor(options: PairwiseSessionEncryptionOptions) {
    this.sessionId = options.sessionId;

    // Compute pairwise secret using ECDH
    const pairwiseSecret = computePairwiseSecret(
      options.myPrivateKey,
      options.peerPublicKey
    );

    // Derive session key from pairwise secret
    this.sessionKey = deriveSessionKeyFromPair(
      pairwiseSecret.secret,
      options.sessionId
    );
  }

  /**
   * Encrypt a message for transmission
   */
  encryptMessage(message: SessionMessage): EncryptedSessionMessage {
    const plaintext = JSON.stringify({
      type: message.type,
      content: message.content,
    });

    const plaintextBytes = stringToBytes(plaintext);
    const encrypted = encrypt(this.sessionKey, plaintextBytes);

    return {
      id: message.id,
      sessionId: message.sessionId,
      payload: toBase64(encrypted.ciphertext),
      nonce: toBase64(encrypted.nonce),
      timestamp: message.timestamp.getTime(),
      sequence: message.sequence,
    };
  }

  /**
   * Decrypt a received message
   */
  decryptMessage(
    encrypted: EncryptedSessionMessage
  ): Pick<SessionMessage, "type" | "content"> {
    const ciphertext = fromBase64(encrypted.payload);
    const nonce = fromBase64(encrypted.nonce);

    const plaintextBytes = decrypt(this.sessionKey, nonce, ciphertext);
    const plaintext = bytesToString(plaintextBytes);

    const parsed = JSON.parse(plaintext) as {
      type: SessionMessage["type"];
      content: string;
    };

    return {
      type: parsed.type,
      content: parsed.content,
    };
  }

  /**
   * Encrypt arbitrary data
   */
  encrypt(data: string): { payload: string; nonce: string } {
    const dataBytes = stringToBytes(data);
    const encrypted = encrypt(this.sessionKey, dataBytes);
    return {
      payload: toBase64(encrypted.ciphertext),
      nonce: toBase64(encrypted.nonce),
    };
  }

  /**
   * Decrypt arbitrary data
   */
  decrypt(payload: string, nonce: string): string {
    const ciphertext = fromBase64(payload);
    const nonceBytes = fromBase64(nonce);
    const plaintextBytes = decrypt(this.sessionKey, nonceBytes, ciphertext);
    return bytesToString(plaintextBytes);
  }

  /**
   * Get session ID
   */
  getSessionId(): string {
    return this.sessionId;
  }

  /**
   * Clear the session key from memory
   */
  clear(): void {
    this.sessionKey.fill(0);
  }
}

/**
 * Options for creating a pairwise encryption manager
 */
export interface PairwiseEncryptionManagerOptions {
  /** My device's private key */
  myPrivateKey: Uint8Array;
}

/**
 * Pairwise encryption manager for multiple sessions with different peers
 *
 * Unlike EncryptionManager which uses a shared master key, this manager
 * creates unique encryption contexts for each peer using ECDH-derived
 * pairwise secrets.
 */
export class PairwiseEncryptionManager {
  private myPrivateKey: Uint8Array;
  private sessions: Map<string, PairwiseSessionEncryption> = new Map();

  constructor(options: PairwiseEncryptionManagerOptions) {
    this.myPrivateKey = options.myPrivateKey;
  }

  /**
   * Get or create encryption context for a session with a specific peer
   */
  getSessionEncryption(
    sessionId: string,
    peerPublicKey: Uint8Array
  ): PairwiseSessionEncryption {
    let encryption = this.sessions.get(sessionId);
    if (!encryption) {
      encryption = new PairwiseSessionEncryption({
        sessionId,
        myPrivateKey: this.myPrivateKey,
        peerPublicKey,
      });
      this.sessions.set(sessionId, encryption);
    }
    return encryption;
  }

  /**
   * Remove encryption context for a session
   */
  removeSession(sessionId: string): boolean {
    const encryption = this.sessions.get(sessionId);
    if (encryption) {
      encryption.clear();
      return this.sessions.delete(sessionId);
    }
    return false;
  }

  /**
   * Encrypt a message for a specific peer
   */
  encryptMessage(
    message: SessionMessage,
    peerPublicKey: Uint8Array
  ): EncryptedSessionMessage {
    const encryption = this.getSessionEncryption(
      message.sessionId,
      peerPublicKey
    );
    return encryption.encryptMessage(message);
  }

  /**
   * Decrypt a message from a specific peer
   */
  decryptMessage(
    encrypted: EncryptedSessionMessage,
    peerPublicKey: Uint8Array
  ): Pick<SessionMessage, "type" | "content"> {
    const encryption = this.getSessionEncryption(
      encrypted.sessionId,
      peerPublicKey
    );
    return encryption.decryptMessage(encrypted);
  }

  /**
   * Clear all session keys
   */
  clear(): void {
    for (const encryption of this.sessions.values()) {
      encryption.clear();
    }
    this.sessions.clear();
    this.myPrivateKey.fill(0);
  }
}

/**
 * Encryption manager for multiple sessions
 * @deprecated Use PairwiseEncryptionManager for device-rooted trust model
 */
export class EncryptionManager {
  private masterKey: Uint8Array;
  private sessions: Map<string, SessionEncryption> = new Map();

  constructor(masterKey: Uint8Array) {
    this.masterKey = masterKey;
  }

  /**
   * Get or create encryption context for a session
   */
  getSessionEncryption(sessionId: string): SessionEncryption {
    let encryption = this.sessions.get(sessionId);
    if (!encryption) {
      encryption = new SessionEncryption(this.masterKey, sessionId);
      this.sessions.set(sessionId, encryption);
    }
    return encryption;
  }

  /**
   * Remove encryption context for a session
   */
  removeSession(sessionId: string): boolean {
    const encryption = this.sessions.get(sessionId);
    if (encryption) {
      encryption.clear();
      return this.sessions.delete(sessionId);
    }
    return false;
  }

  /**
   * Encrypt a message
   */
  encryptMessage(message: SessionMessage): EncryptedSessionMessage {
    const encryption = this.getSessionEncryption(message.sessionId);
    return encryption.encryptMessage(message);
  }

  /**
   * Decrypt a message
   */
  decryptMessage(
    encrypted: EncryptedSessionMessage
  ): Pick<SessionMessage, "type" | "content"> {
    const encryption = this.getSessionEncryption(encrypted.sessionId);
    return encryption.decryptMessage(encrypted);
  }

  /**
   * Clear all session keys
   */
  clear(): void {
    for (const encryption of this.sessions.values()) {
      encryption.clear();
    }
    this.sessions.clear();
    // Clear master key
    this.masterKey.fill(0);
  }
}

/**
 * Create a session encryption context
 * @deprecated Use createPairwiseSessionEncryption for device-rooted trust model
 */
export function createSessionEncryption(
  masterKey: Uint8Array,
  sessionId: string
): SessionEncryption {
  return new SessionEncryption(masterKey, sessionId);
}

/**
 * Create an encryption manager
 * @deprecated Use createPairwiseEncryptionManager for device-rooted trust model
 */
export function createEncryptionManager(
  masterKey: Uint8Array
): EncryptionManager {
  return new EncryptionManager(masterKey);
}

/**
 * Create a pairwise session encryption context
 */
export function createPairwiseSessionEncryption(
  options: PairwiseSessionEncryptionOptions
): PairwiseSessionEncryption {
  return new PairwiseSessionEncryption(options);
}

/**
 * Create a pairwise encryption manager
 */
export function createPairwiseEncryptionManager(
  options: PairwiseEncryptionManagerOptions
): PairwiseEncryptionManager {
  return new PairwiseEncryptionManager(options);
}
