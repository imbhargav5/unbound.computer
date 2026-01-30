import { z } from "zod";

/** ULID gives you time-sort + uniqueness */
export const UlidSchema = z.string().regex(/^[0-9A-HJKMNP-TV-Z]{26}$/);

/** Which stream this event belongs to */
export const ChannelSchema = z.enum([
  "chatSecret",
  "communication",
  "conversation",
]);

/** Encrypted payload relay must not inspect */
export const EncryptedPayloadSchema = z.object({
  alg: z.literal("xchacha20-poly1305"),
  nonce: z.string(), // base64
  ciphertext: z.string(), // base64
});

/** Relay envelope */
export const RelayEnvelopeSchema = z.object({
  env: z.enum(["dev", "staging", "prod"]),
  sessionId: UlidSchema,
  channel: ChannelSchema,

  /** client-generated id for idempotency */
  eventId: UlidSchema,

  payload: EncryptedPayloadSchema,

  meta: z.object({
    clientTs: z.number(),
    schemaVersion: z.literal(1),
  }),
});

export type RelayEnvelope = z.infer<typeof RelayEnvelopeSchema>;
export type Channel = z.infer<typeof ChannelSchema>;
export type EncryptedPayload = z.infer<typeof EncryptedPayloadSchema>;
