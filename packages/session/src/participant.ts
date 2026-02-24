/**
 * Participant Session Encryption
 *
 * Used by participants (viewers) to decrypt messages from the host.
 */

import {
  computePairwiseSecret,
  decrypt,
  deriveSessionKeyFromPair,
  fromBase64,
} from "@unbound/crypto";
import type { EncryptedParticipantMessage } from "./types.js";

/**
 * Options for creating a participant encryption context
 */
export interface ParticipantEncryptionOptions {
  /** Host's public key (base64) */
  hostPublicKey: string;
  /** Participant's private key */
  participantPrivateKey: Uint8Array;
  /** Session ID */
  sessionId: string;
}

/**
 * Encryption context for a session participant (viewer/controller)
 */
export class ParticipantEncryption {
  private sessionKey: Uint8Array;
  private sessionId: string;

  constructor(options: ParticipantEncryptionOptions) {
    this.sessionId = options.sessionId;

    // Compute pairwise secret with host
    const hostPublicKeyBytes = fromBase64(options.hostPublicKey);
    const pairwiseSecret = computePairwiseSecret(
      options.participantPrivateKey,
      hostPublicKeyBytes
    );

    // Derive session key (same as host computed for us)
    this.sessionKey = deriveSessionKeyFromPair(
      pairwiseSecret.secret,
      options.sessionId
    );
  }

  /**
   * Decrypt a message from the host
   */
  decryptMessage(encrypted: EncryptedParticipantMessage): Uint8Array {
    const payload = fromBase64(encrypted.payload);
    const nonce = fromBase64(encrypted.nonce);
    return decrypt(this.sessionKey, nonce, payload);
  }

  /**
   * Decrypt a base64 sealed message (nonce + ciphertext)
   */
  decryptSealed(sealed: string): Uint8Array {
    const sealedBytes = fromBase64(sealed);
    const nonce = sealedBytes.slice(0, 24);
    const ciphertext = sealedBytes.slice(24);
    return decrypt(this.sessionKey, nonce, ciphertext);
  }

  /**
   * Get the session ID
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
 * Create a participant encryption context
 */
export function createParticipantEncryption(
  options: ParticipantEncryptionOptions
): ParticipantEncryption {
  return new ParticipantEncryption(options);
}
