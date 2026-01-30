import { z } from "zod";
import { AckFrame } from "./ack";
import { HandshakeEvent } from "./handshake-events";
import { SessionEvent } from "./session-events";

/* ---------------- UNBOUND EVENT ---------------- */

export const UnboundEvent = z.union([HandshakeEvent, SessionEvent]);

/* ---------------- ANY EVENT (WIRE FRAME) ---------------- */

export const AnyEvent = z.union([UnboundEvent, AckFrame]);
