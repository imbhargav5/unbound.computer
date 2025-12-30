import { z } from "zod";

/**
 * Pairing request - sent by new device
 * Contains the ephemeral public key for key exchange
 */
export const PairingRequestSchema = z.object({
  type: z.literal("PAIRING_REQUEST"),
  deviceId: z.string().uuid(),
  deviceName: z.string(),
  publicKey: z.string(), // Base64-encoded X25519 public key
  timestamp: z.number(),
});

/**
 * Pairing response - sent by trusted device
 * Contains the encrypted Master Key
 */
export const PairingResponseSchema = z.object({
  type: z.literal("PAIRING_RESPONSE"),
  deviceId: z.string().uuid(),
  encryptedMasterKey: z.string(), // Base64-encoded encrypted Master Key
  nonce: z.string(), // Base64-encoded nonce
  success: z.boolean(),
  error: z.string().optional(),
});

/**
 * Pairing confirmation - sent by new device after receiving Master Key
 */
export const PairingConfirmationSchema = z.object({
  type: z.literal("PAIRING_CONFIRMATION"),
  deviceId: z.string().uuid(),
  success: z.boolean(),
  error: z.string().optional(),
});

/**
 * Union of all pairing messages
 */
export const PairingMessageSchema = z.discriminatedUnion("type", [
  PairingRequestSchema,
  PairingResponseSchema,
  PairingConfirmationSchema,
]);

export type PairingRequest = z.infer<typeof PairingRequestSchema>;
export type PairingResponse = z.infer<typeof PairingResponseSchema>;
export type PairingConfirmation = z.infer<typeof PairingConfirmationSchema>;
export type PairingMessage = z.infer<typeof PairingMessageSchema>;

/**
 * Validate a pairing message
 */
export function validatePairingMessage(data: unknown): PairingMessage {
  return PairingMessageSchema.parse(data);
}

/**
 * Safe parse a pairing message
 */
export function parsePairingMessage(
  data: unknown
):
  | { success: true; data: PairingMessage }
  | { success: false; error: z.ZodError } {
  const result = PairingMessageSchema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  return { success: false, error: result.error };
}

/**
 * Create a pairing request
 */
export function createPairingRequest(
  deviceId: string,
  deviceName: string,
  publicKey: string
): PairingRequest {
  return {
    type: "PAIRING_REQUEST",
    deviceId,
    deviceName,
    publicKey,
    timestamp: Date.now(),
  };
}

/**
 * Create a pairing response
 */
export function createPairingResponse(
  deviceId: string,
  encryptedMasterKey: string,
  nonce: string,
  success: boolean,
  error?: string
): PairingResponse {
  return {
    type: "PAIRING_RESPONSE",
    deviceId,
    encryptedMasterKey,
    nonce,
    success,
    error,
  };
}

/**
 * Create a pairing confirmation
 */
export function createPairingConfirmation(
  deviceId: string,
  success: boolean,
  error?: string
): PairingConfirmation {
  return {
    type: "PAIRING_CONFIRMATION",
    deviceId,
    success,
    error,
  };
}
