import type { WebSocket } from "ws";
import { validateDeviceToken } from "../auth/index.js";
import { connectionManager, presenceManager } from "../managers/index.js";
import type { AuthMessage } from "../types/index.js";
import { createAuthFailure, createAuthSuccess } from "../types/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "auth-handler" });

/**
 * Handle AUTH message from client
 */
export async function handleAuth(
  ws: WebSocket,
  deviceId: string,
  message: AuthMessage
): Promise<boolean> {
  const authStartTime = Date.now();
  log.debug(
    { tempDeviceId: deviceId, claimedDeviceId: message.deviceId },
    "Processing AUTH message - validating device token"
  );

  // Validate the device token
  const result = await validateDeviceToken(
    message.deviceToken,
    message.deviceId
  );

  const validationDuration = Date.now() - authStartTime;

  if (!(result.valid && result.context)) {
    log.warn(
      {
        tempDeviceId: deviceId,
        claimedDeviceId: message.deviceId,
        error: result.error,
        validationDurationMs: validationDuration,
      },
      "Auth failed - token validation rejected"
    );
    ws.send(JSON.stringify(createAuthFailure(result.error || "Auth failed")));
    return false;
  }

  log.debug(
    {
      tempDeviceId: deviceId,
      deviceId: result.context.deviceId,
      userId: result.context.userId,
      deviceName: result.context.deviceName,
      validationDurationMs: validationDuration,
    },
    "Device token validated successfully"
  );

  // Mark connection as authenticated
  const authenticated = connectionManager.authenticate(
    deviceId,
    result.context
  );
  if (!authenticated) {
    log.error(
      {
        tempDeviceId: deviceId,
        deviceId: result.context.deviceId,
        userId: result.context.userId,
      },
      "Failed to authenticate connection - connection manager rejected"
    );
    ws.send(JSON.stringify(createAuthFailure("Internal error")));
    return false;
  }

  // Record presence
  presenceManager.deviceConnected(deviceId);

  // Send success response
  ws.send(JSON.stringify(createAuthSuccess()));

  log.info(
    {
      deviceId: result.context.deviceId,
      deviceName: result.context.deviceName,
      userId: result.context.userId,
      authDurationMs: Date.now() - authStartTime,
    },
    "Device authenticated successfully"
  );

  return true;
}
