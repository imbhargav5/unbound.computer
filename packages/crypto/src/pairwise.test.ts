import { describe, expect, it } from "vitest";
import {
  computePairwiseSecret,
  deriveMessageKey,
  deriveSessionKeyFromPair,
  deriveWebSessionKeyFromDevice,
  generateSessionKey,
  orderDeviceIds,
  PAIRWISE_CONTEXT,
} from "./pairwise.js";
import { KEY_SIZE } from "./types.js";
import { generateKeyPair } from "./x25519.js";

describe("pairwise crypto", () => {
  describe("computePairwiseSecret", () => {
    it("should compute a 32-byte shared secret", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();

      const secretFromA = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );
      const secretFromB = computePairwiseSecret(
        keyPairB.privateKey,
        keyPairA.publicKey
      );

      expect(secretFromA.secret).toHaveLength(KEY_SIZE.SESSION_KEY);
      expect(secretFromB.secret).toHaveLength(KEY_SIZE.SESSION_KEY);
    });

    it("should produce the same secret from both parties (ECDH symmetry)", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();

      const secretFromA = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );
      const secretFromB = computePairwiseSecret(
        keyPairB.privateKey,
        keyPairA.publicKey
      );

      // ECDH is symmetric: ECDH(priv_A, pub_B) === ECDH(priv_B, pub_A)
      expect(secretFromA.secret).toEqual(secretFromB.secret);
    });

    it("should produce different secrets for different key pairs", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const keyPairC = generateKeyPair();

      const secretAB = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );
      const secretAC = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairC.publicKey
      );
      const secretBC = computePairwiseSecret(
        keyPairB.privateKey,
        keyPairC.publicKey
      );

      expect(secretAB.secret).not.toEqual(secretAC.secret);
      expect(secretAB.secret).not.toEqual(secretBC.secret);
      expect(secretAC.secret).not.toEqual(secretBC.secret);
    });

    it("should be deterministic for the same key pairs", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();

      const secret1 = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );
      const secret2 = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      expect(secret1.secret).toEqual(secret2.secret);
    });
  });

  describe("deriveSessionKeyFromPair", () => {
    it("should derive a 32-byte session key", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      const sessionKey = deriveSessionKeyFromPair(
        pairwiseSecret,
        "test-session-id"
      );

      expect(sessionKey).toHaveLength(KEY_SIZE.SESSION_KEY);
    });

    it("should derive the same key for both parties", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();

      const secretFromA = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );
      const secretFromB = computePairwiseSecret(
        keyPairB.privateKey,
        keyPairA.publicKey
      );

      const sessionId = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";

      const keyFromA = deriveSessionKeyFromPair(secretFromA, sessionId);
      const keyFromB = deriveSessionKeyFromPair(secretFromB, sessionId);

      expect(keyFromA).toEqual(keyFromB);
    });

    it("should derive different keys for different session IDs", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      const key1 = deriveSessionKeyFromPair(pairwiseSecret, "session-1");
      const key2 = deriveSessionKeyFromPair(pairwiseSecret, "session-2");

      expect(key1).not.toEqual(key2);
    });

    it("should derive different keys for different contexts", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );
      const sessionId = "test-session";

      const key1 = deriveSessionKeyFromPair(
        pairwiseSecret,
        sessionId,
        PAIRWISE_CONTEXT.SESSION
      );
      const key2 = deriveSessionKeyFromPair(
        pairwiseSecret,
        sessionId,
        PAIRWISE_CONTEXT.MESSAGE
      );

      expect(key1).not.toEqual(key2);
    });

    it("should accept raw Uint8Array as pairwise secret", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      const keyFromObject = deriveSessionKeyFromPair(
        pairwiseSecret,
        "test-session"
      );
      const keyFromRaw = deriveSessionKeyFromPair(
        pairwiseSecret.secret,
        "test-session"
      );

      expect(keyFromObject).toEqual(keyFromRaw);
    });

    it("should throw for invalid secret length", () => {
      const invalidSecret = new Uint8Array(16); // Too short

      expect(() =>
        deriveSessionKeyFromPair(invalidSecret, "test-session")
      ).toThrow("Pairwise secret must be 32 bytes");
    });
  });

  describe("deriveMessageKey", () => {
    it("should derive a 32-byte message key", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      const messageKey = deriveMessageKey(pairwiseSecret, "control");

      expect(messageKey).toHaveLength(KEY_SIZE.SESSION_KEY);
    });

    it("should derive different keys for different purposes", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      const controlKey = deriveMessageKey(pairwiseSecret, "control");
      const streamKey = deriveMessageKey(pairwiseSecret, "stream");
      const ackKey = deriveMessageKey(pairwiseSecret, "ack");

      expect(controlKey).not.toEqual(streamKey);
      expect(controlKey).not.toEqual(ackKey);
      expect(streamKey).not.toEqual(ackKey);
    });

    it("should derive different keys for different counters", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      const key0 = deriveMessageKey(pairwiseSecret, "control", 0);
      const key1 = deriveMessageKey(pairwiseSecret, "control", 1);
      const key2 = deriveMessageKey(pairwiseSecret, "control", 2);

      expect(key0).not.toEqual(key1);
      expect(key0).not.toEqual(key2);
      expect(key1).not.toEqual(key2);
    });

    it("should be deterministic", () => {
      const keyPairA = generateKeyPair();
      const keyPairB = generateKeyPair();
      const pairwiseSecret = computePairwiseSecret(
        keyPairA.privateKey,
        keyPairB.publicKey
      );

      const key1 = deriveMessageKey(pairwiseSecret, "control", 0);
      const key2 = deriveMessageKey(pairwiseSecret, "control", 0);

      expect(key1).toEqual(key2);
    });

    it("should throw for invalid secret length", () => {
      const invalidSecret = new Uint8Array(64); // Too long

      expect(() => deriveMessageKey(invalidSecret, "control")).toThrow(
        "Pairwise secret must be 32 bytes"
      );
    });
  });

  describe("generateSessionKey", () => {
    it("should generate a 32-byte random key", () => {
      const key = generateSessionKey();

      expect(key).toHaveLength(KEY_SIZE.SESSION_KEY);
      expect(key).toBeInstanceOf(Uint8Array);
    });

    it("should generate unique keys each time", () => {
      const keys = Array.from({ length: 10 }, () => generateSessionKey());

      for (let i = 0; i < keys.length; i++) {
        for (let j = i + 1; j < keys.length; j++) {
          expect(keys[i]).not.toEqual(keys[j]);
        }
      }
    });

    it("should generate cryptographically random data", () => {
      const key = generateSessionKey();

      // Very basic entropy check - at least some bytes should be non-zero
      const nonZeroCount = key.filter((b) => b !== 0).length;
      expect(nonZeroCount).toBeGreaterThan(20); // Most bytes should be non-zero
    });
  });

  describe("deriveWebSessionKeyFromDevice", () => {
    it("should derive a 32-byte web session key", () => {
      const deviceKeyPair = generateKeyPair();
      const webKeyPair = generateKeyPair();

      const sessionKey = deriveWebSessionKeyFromDevice(
        deviceKeyPair.privateKey,
        webKeyPair.publicKey,
        "web-session-123"
      );

      expect(sessionKey).toHaveLength(KEY_SIZE.SESSION_KEY);
    });

    it("should allow web client to derive same key", () => {
      const deviceKeyPair = generateKeyPair();
      const webKeyPair = generateKeyPair();
      const sessionId = "web-session-abc123";

      const keyFromDevice = deriveWebSessionKeyFromDevice(
        deviceKeyPair.privateKey,
        webKeyPair.publicKey,
        sessionId
      );
      const keyFromWeb = deriveWebSessionKeyFromDevice(
        webKeyPair.privateKey,
        deviceKeyPair.publicKey,
        sessionId
      );

      // Both should derive the same key due to ECDH symmetry
      expect(keyFromDevice).toEqual(keyFromWeb);
    });

    it("should derive different keys for different session IDs", () => {
      const deviceKeyPair = generateKeyPair();
      const webKeyPair = generateKeyPair();

      const key1 = deriveWebSessionKeyFromDevice(
        deviceKeyPair.privateKey,
        webKeyPair.publicKey,
        "session-1"
      );
      const key2 = deriveWebSessionKeyFromDevice(
        deviceKeyPair.privateKey,
        webKeyPair.publicKey,
        "session-2"
      );

      expect(key1).not.toEqual(key2);
    });

    it("should derive different keys for different web clients", () => {
      const deviceKeyPair = generateKeyPair();
      const webKeyPair1 = generateKeyPair();
      const webKeyPair2 = generateKeyPair();
      const sessionId = "test-session";

      const key1 = deriveWebSessionKeyFromDevice(
        deviceKeyPair.privateKey,
        webKeyPair1.publicKey,
        sessionId
      );
      const key2 = deriveWebSessionKeyFromDevice(
        deviceKeyPair.privateKey,
        webKeyPair2.publicKey,
        sessionId
      );

      expect(key1).not.toEqual(key2);
    });
  });

  describe("orderDeviceIds", () => {
    it("should order device IDs lexicographically", () => {
      const [smaller, larger] = orderDeviceIds("zzz-device", "aaa-device");

      expect(smaller).toBe("aaa-device");
      expect(larger).toBe("zzz-device");
    });

    it("should return IDs in same order if already ordered", () => {
      const [smaller, larger] = orderDeviceIds("aaa-device", "zzz-device");

      expect(smaller).toBe("aaa-device");
      expect(larger).toBe("zzz-device");
    });

    it("should handle UUID ordering correctly", () => {
      const uuid1 = "11111111-1111-1111-1111-111111111111";
      const uuid2 = "99999999-9999-9999-9999-999999999999";

      const [smaller, larger] = orderDeviceIds(uuid2, uuid1);

      expect(smaller).toBe(uuid1);
      expect(larger).toBe(uuid2);
    });

    it("should be deterministic regardless of input order", () => {
      const id1 = "device-a";
      const id2 = "device-b";

      const [a1, b1] = orderDeviceIds(id1, id2);
      const [a2, b2] = orderDeviceIds(id2, id1);

      expect(a1).toBe(a2);
      expect(b1).toBe(b2);
    });
  });

  describe("PAIRWISE_CONTEXT", () => {
    it("should have all expected context strings", () => {
      expect(PAIRWISE_CONTEXT.SESSION).toBe("unbound-session-v1");
      expect(PAIRWISE_CONTEXT.MESSAGE).toBe("unbound-message-v1");
      expect(PAIRWISE_CONTEXT.WEB_SESSION).toBe("unbound-web-session-v1");
    });
  });
});
