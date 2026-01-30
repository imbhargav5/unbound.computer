import { z } from "zod";

/**
 * AUTH message sent by client after WebSocket connection
 */
export const AuthMessageSchema = z.object({
  type: z.literal("AUTH"),
  deviceToken: z.string().min(1),
  deviceId: z.string().uuid(),
});

export type AuthMessage = z.infer<typeof AuthMessageSchema>;

/**
 * AUTH_RESULT event sent by relay after validating auth
 */
export const AuthResultSchema = z.object({
  type: z.literal("AUTH_RESULT"),
  success: z.boolean(),
  error: z.string().optional(),
});

export type AuthResult = z.infer<typeof AuthResultSchema>;

/**
 * Authentication context after successful auth
 */
export interface AuthContext {
  userId: string;
  deviceId: string;
  deviceName?: string;
}

/**
 * Create an AUTH_RESULT success event
 */
export function createAuthSuccess(): AuthResult {
  return {
    type: "AUTH_RESULT",
    success: true,
  };
}

/**
 * Create an AUTH_RESULT failure event
 */
export function createAuthFailure(error: string): AuthResult {
  return {
    type: "AUTH_RESULT",
    success: false,
    error,
  };
}
