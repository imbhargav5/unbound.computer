import { z } from "zod";
import { BaseUnboundEvent } from "./base";

/* ---------------- HANDSHAKE BASE ---------------- */

export const HandshakeBaseEvent = BaseUnboundEvent.extend({
  plane: z.literal("HANDSHAKE"),
  sessionId: z.null(),
});

/* ---------------- HANDSHAKE EVENTS ---------------- */

export const PairRequestEvent = HandshakeBaseEvent.extend({
  type: z.literal("PAIR_REQUEST"),
  payload: z.object({
    remoteDeviceName: z.string(),
    remoteDeviceId: z.string(),
    remotePublicKey: z.string(),
  }),
});

export const PairAcceptedEvent = HandshakeBaseEvent.extend({
  type: z.literal("PAIR_ACCEPTED"),
  payload: z.object({
    // executor is the device that will be used to execute the session
    executorDeviceId: z.string(),
    executorPublicKey: z.string(),
    executorDeviceName: z.string(),
  }),
});

/* ---- Special handshake: SESSION_CREATED (exception) ---- */

// sessionId uses flexible string validation to support both UUID and ULID formats
export const SessionCreatedEvent = BaseUnboundEvent.extend({
  plane: z.literal("HANDSHAKE"),
  type: z.literal("SESSION_CREATED"),
  sessionId: z.string().min(1),
  payload: z.object({}),
});

/* ---------------- QR PAIRING EVENTS ---------------- */

// iOS approves pairing via relay
export const PairingApprovedEvent = HandshakeBaseEvent.extend({
  type: z.literal("PAIRING_APPROVED"),
  payload: z.object({
    pairingTokenId: z.string().uuid(),
    approvingDeviceId: z.string().uuid(),
    approvingDeviceName: z.string(),
  }),
});

// Pairing completed successfully
export const PairingCompletedEvent = HandshakeBaseEvent.extend({
  type: z.literal("PAIRING_COMPLETED"),
  payload: z.object({
    pairingTokenId: z.string().uuid(),
  }),
});

// Pairing failed
export const PairingFailedEvent = HandshakeBaseEvent.extend({
  type: z.literal("PAIRING_FAILED"),
  payload: z.object({
    pairingTokenId: z.string().uuid(),
    error: z.string(),
  }),
});

/* ---------------- HANDSHAKE UNION ---------------- */

export const HandshakeEvent = z.discriminatedUnion("type", [
  PairRequestEvent,
  PairAcceptedEvent,
  SessionCreatedEvent,
  PairingApprovedEvent,
  PairingCompletedEvent,
  PairingFailedEvent,
]);
