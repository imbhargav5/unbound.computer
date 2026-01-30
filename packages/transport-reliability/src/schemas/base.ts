import { z } from "zod";
import { UlidSchema } from "./relay-envelope.js";

/* ---------------- SHARED BASE ---------------- */

export const BaseUnboundEvent = z.object({
  opcode: z.literal("EVENT"),
  eventId: UlidSchema,
  createdAt: z.number(), // unix millis
  type: z.string(),
  payload: z.object({}),
});
