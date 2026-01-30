import { ulid } from "ulid";
import { describe, expect, it } from "vitest";
import {
  ChannelSchema,
  EncryptedPayloadSchema,
  RelayEnvelopeSchema,
  UlidSchema,
} from "./relay-envelope";

describe("UlidSchema", () => {
  it("should accept valid ULID", () => {
    const validUlid = ulid();
    expect(() => UlidSchema.parse(validUlid)).not.toThrow();
  });

  it("should reject invalid ULID - wrong length", () => {
    expect(() => UlidSchema.parse("ABC123")).toThrow();
  });

  it("should reject invalid ULID - invalid characters", () => {
    expect(() => UlidSchema.parse("01ARZ3NDEKTSV4RRFFQ69I123")).toThrow();
  });

  it("should reject non-string values", () => {
    expect(() => UlidSchema.parse(123)).toThrow();
    expect(() => UlidSchema.parse(null)).toThrow();
  });
});

describe("ChannelSchema", () => {
  it("should accept chatSecret channel", () => {
    expect(() => ChannelSchema.parse("chatSecret")).not.toThrow();
  });

  it("should accept communication channel", () => {
    expect(() => ChannelSchema.parse("communication")).not.toThrow();
  });

  it("should accept conversation channel", () => {
    expect(() => ChannelSchema.parse("conversation")).not.toThrow();
  });

  it("should reject invalid channel", () => {
    expect(() => ChannelSchema.parse("invalidChannel")).toThrow();
  });
});

describe("EncryptedPayloadSchema", () => {
  it("should accept valid encrypted payload", () => {
    const payload = {
      alg: "xchacha20-poly1305" as const,
      nonce: "base64encodednonce==",
      ciphertext: "base64encodedciphertext==",
    };

    expect(() => EncryptedPayloadSchema.parse(payload)).not.toThrow();
  });

  it("should reject invalid algorithm", () => {
    const payload = {
      alg: "aes-256-gcm",
      nonce: "base64encodednonce==",
      ciphertext: "base64encodedciphertext==",
    };

    expect(() => EncryptedPayloadSchema.parse(payload)).toThrow();
  });

  it("should reject missing nonce", () => {
    const payload = {
      alg: "xchacha20-poly1305" as const,
      ciphertext: "base64encodedciphertext==",
    };

    expect(() => EncryptedPayloadSchema.parse(payload)).toThrow();
  });

  it("should reject missing ciphertext", () => {
    const payload = {
      alg: "xchacha20-poly1305" as const,
      nonce: "base64encodednonce==",
    };

    expect(() => EncryptedPayloadSchema.parse(payload)).toThrow();
  });
});

describe("RelayEnvelopeSchema", () => {
  const validEnvelope = {
    env: "dev" as const,
    sessionId: ulid(),
    channel: "conversation" as const,
    eventId: ulid(),
    payload: {
      alg: "xchacha20-poly1305" as const,
      nonce: "base64encodednonce==",
      ciphertext: "base64encodedciphertext==",
    },
    meta: {
      clientTs: Date.now(),
      schemaVersion: 1 as const,
    },
  };

  it("should accept valid relay envelope with dev environment", () => {
    expect(() => RelayEnvelopeSchema.parse(validEnvelope)).not.toThrow();
  });

  it("should accept valid relay envelope with staging environment", () => {
    const envelope = { ...validEnvelope, env: "staging" as const };
    expect(() => RelayEnvelopeSchema.parse(envelope)).not.toThrow();
  });

  it("should accept valid relay envelope with prod environment", () => {
    const envelope = { ...validEnvelope, env: "prod" as const };
    expect(() => RelayEnvelopeSchema.parse(envelope)).not.toThrow();
  });

  it("should accept chatSecret channel", () => {
    const envelope = { ...validEnvelope, channel: "chatSecret" as const };
    expect(() => RelayEnvelopeSchema.parse(envelope)).not.toThrow();
  });

  it("should accept communication channel", () => {
    const envelope = { ...validEnvelope, channel: "communication" as const };
    expect(() => RelayEnvelopeSchema.parse(envelope)).not.toThrow();
  });

  it("should reject invalid environment", () => {
    const envelope = { ...validEnvelope, env: "production" };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject invalid channel", () => {
    const envelope = { ...validEnvelope, channel: "unknown" };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject invalid sessionId ULID", () => {
    const envelope = { ...validEnvelope, sessionId: "invalid-ulid" };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject invalid eventId ULID", () => {
    const envelope = { ...validEnvelope, eventId: "invalid-ulid" };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject invalid payload algorithm", () => {
    const envelope = {
      ...validEnvelope,
      payload: {
        ...validEnvelope.payload,
        alg: "aes-256-gcm",
      },
    };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject missing payload nonce", () => {
    const envelope = {
      ...validEnvelope,
      payload: {
        alg: "xchacha20-poly1305" as const,
        ciphertext: "base64encodedciphertext==",
      },
    };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject invalid schema version", () => {
    const envelope = {
      ...validEnvelope,
      meta: {
        ...validEnvelope.meta,
        schemaVersion: 2,
      },
    };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject missing meta fields", () => {
    const envelope = {
      ...validEnvelope,
      meta: {
        clientTs: Date.now(),
      },
    };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should reject non-number clientTs", () => {
    const envelope = {
      ...validEnvelope,
      meta: {
        clientTs: "2024-01-01",
        schemaVersion: 1 as const,
      },
    };
    expect(() => RelayEnvelopeSchema.parse(envelope)).toThrow();
  });

  it("should parse and extract correct types", () => {
    const result = RelayEnvelopeSchema.parse(validEnvelope);

    expect(result.env).toBe("dev");
    expect(result.channel).toBe("conversation");
    expect(result.payload.alg).toBe("xchacha20-poly1305");
    expect(result.meta.schemaVersion).toBe(1);
    expect(typeof result.meta.clientTs).toBe("number");
  });
});
