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
  log.debug({ deviceId }, "Processing AUTH message");

  // Validate the device token
  const result = await validateDeviceToken(
    message.deviceToken,
    message.deviceId
  );

  if (!(result.valid && result.context)) {
    log.warn({ deviceId, error: result.error }, "Auth failed");
    ws.send(JSON.stringify(createAuthFailure(result.error || "Auth failed")));
    return false;
  }

  // Mark connection as authenticated
  const authenticated = connectionManager.authenticate(
    deviceId,
    result.context
  );
  if (!authenticated) {
    log.error({ deviceId }, "Failed to authenticate connection");
    ws.send(JSON.stringify(createAuthFailure("Internal error")));
    return false;
  }

  // Record presence
  presenceManager.deviceConnected(deviceId);

  // Send success response
  ws.send(JSON.stringify(createAuthSuccess()));

  log.info(
    { deviceId, userId: result.context.userId },
    "Client authenticated successfully"
  );

  return true;
}
