import { z } from "zod";
import { UlidSchema } from "./relay-envelope";

/* ---------------- ACK FRAME ---------------- */

export const AckFrame = z.object({
  opcode: z.literal("ACK"),
  eventId: UlidSchema,
});
