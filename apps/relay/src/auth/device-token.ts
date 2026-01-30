import type { AuthContext } from "../types/index.js";
import { AuthError, createLogger } from "../utils/index.js";
import { supabaseAdmin } from "./supabase.js";

const log = createLogger({ module: "device-token" });

/**
 * Token validation result
 */
export interface TokenValidationResult {
  valid: boolean;
  context?: AuthContext;
  error?: string;
}

/**
 * Validate a device token and return the auth context
 *
 * The device token is a Supabase JWT access token.
 * We validate it and then verify the device exists in the database.
 */
export async function validateDeviceToken(
  deviceToken: string,
  deviceId: string
): Promise<TokenValidationResult> {
  try {
    // Validate the JWT token with Supabase
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(deviceToken);

    if (authError || !user) {
      log.warn({ error: authError?.message }, "Token validation failed");
      return {
        valid: false,
        error: authError?.message || "Invalid token",
      };
    }

    // Look up the device in the database
    const { data: device, error: deviceError } = await supabaseAdmin
      .from("devices")
      .select("id, user_id, name, device_type, is_active")
      .eq("id", deviceId)
      .eq("user_id", user.id)
      .single();

    if (deviceError || !device) {
      log.warn(
        { deviceId, userId: user.id, error: deviceError?.message },
        "Device not found or not owned by user"
      );
      return {
        valid: false,
        error: "Device not found or not authorized",
      };
    }

    // Check if device is active
    if (!device.is_active) {
      log.warn({ deviceId }, "Device is not active");
      return {
        valid: false,
        error: "Device is not active",
      };
    }

    // Update last_seen_at
    await supabaseAdmin
      .from("devices")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("id", deviceId);

    log.debug(
      { deviceId, userId: user.id, deviceName: device.name },
      "Token validated successfully"
    );

    return {
      valid: true,
      context: {
        userId: user.id,
        deviceId,
        deviceName: device.name,
      },
    };
  } catch (error) {
    log.error({ error }, "Token validation error");
    throw new AuthError("Token validation failed");
  }
}
