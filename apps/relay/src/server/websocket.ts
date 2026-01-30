import type { IncomingMessage, Server } from "node:http";
import { WebSocketServer } from "ws";
import { validateDeviceToken } from "../auth/index.js";
import { handleConnection } from "../handlers/index.js";
import type { AuthContext } from "../types/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "websocket-server" });

// Store auth context for verified connections (cleared after connection event)
const pendingAuthContexts = new WeakMap<IncomingMessage, AuthContext>();

// Validation timeout in milliseconds
const VALIDATION_TIMEOUT_MS = 5000;

/**
 * Create and attach WebSocket server to HTTP server
 */
export function createWebSocketServer(httpServer: Server): WebSocketServer {
  const wss = new WebSocketServer({
    server: httpServer,
    path: "/",
    verifyClient: async (info, callback) => {
      const ip = info.req.socket.remoteAddress;
      const authHeader = info.req.headers.authorization;
      const deviceId = info.req.headers["x-device-id"];
      const deviceType = info.req.headers["x-device-type"];

      log.debug(
        { ip, deviceType, deviceId: deviceId?.slice(0, 8) },
        "WebSocket upgrade request - validating credentials"
      );

      // Check for required headers
      if (!(authHeader && authHeader.startsWith("Bearer "))) {
        log.warn(
          { ip },
          "WebSocket upgrade rejected - missing Authorization header"
        );
        callback(false, 401, "Missing or invalid Authorization header");
        return;
      }

      if (!deviceId || typeof deviceId !== "string") {
        log.warn(
          { ip },
          "WebSocket upgrade rejected - missing X-Device-ID header"
        );
        callback(false, 401, "Missing X-Device-ID header");
        return;
      }

      const token = authHeader.slice(7); // Remove "Bearer "

      try {
        // Validate with timeout
        const validationPromise = validateDeviceToken(token, deviceId);
        const timeoutPromise = new Promise<{ valid: false; error: string }>(
          (resolve) => {
            setTimeout(
              () => resolve({ valid: false, error: "Validation timeout" }),
              VALIDATION_TIMEOUT_MS
            );
          }
        );

        const result = await Promise.race([validationPromise, timeoutPromise]);

        if (!(result.valid && result.context)) {
          log.warn(
            { ip, deviceId: deviceId.slice(0, 8), error: result.error },
            "WebSocket upgrade rejected - token validation failed"
          );
          callback(false, 401, result.error || "Authentication failed");
          return;
        }

        // Store auth context for use in connection handler
        pendingAuthContexts.set(info.req, result.context);

        log.info(
          {
            ip,
            deviceId: result.context.deviceId,
            deviceName: result.context.deviceName,
            userId: result.context.userId?.slice(0, 8),
          },
          "WebSocket upgrade authorized"
        );

        callback(true);
      } catch (error) {
        log.error(
          { ip, error },
          "WebSocket upgrade rejected - validation error"
        );
        callback(false, 500, "Internal authentication error");
      }
    },
  });

  wss.on("connection", (ws, request) => {
    const authContext = pendingAuthContexts.get(request);
    pendingAuthContexts.delete(request); // Clean up

    if (!authContext) {
      // This should never happen since verifyClient passed
      log.error("Connection accepted without auth context - closing");
      ws.close(4001, "Authentication context missing");
      return;
    }

    const ip = request.socket.remoteAddress;
    const userAgent = request.headers["user-agent"];
    const deviceType = request.headers["x-device-type"];

    log.info(
      {
        ip,
        userAgent,
        deviceType,
        deviceId: authContext.deviceId,
        deviceName: authContext.deviceName,
        userId: authContext.userId?.slice(0, 8),
      },
      "WebSocket connection established (pre-authenticated)"
    );

    handleConnection(ws, authContext);
  });

  wss.on("error", (error) => {
    log.error({ error }, "WebSocket server error");
  });

  wss.on("close", () => {
    log.info("WebSocket server closed");
  });

  log.info("WebSocket server attached to HTTP server");

  return wss;
}
