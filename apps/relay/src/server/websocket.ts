import type { Server } from "node:http";
import { WebSocketServer } from "ws";
import { handleConnection } from "../handlers/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "websocket-server" });

/**
 * Create and attach WebSocket server to HTTP server
 */
export function createWebSocketServer(httpServer: Server): WebSocketServer {
  const wss = new WebSocketServer({
    server: httpServer,
    path: "/",
  });

  wss.on("connection", (ws, request) => {
    const ip = request.socket.remoteAddress;
    log.debug({ ip }, "WebSocket connection established");

    handleConnection(ws);
  });

  wss.on("error", (error) => {
    log.error({ error }, "WebSocket server error");
  });

  log.info("WebSocket server attached to HTTP server");

  return wss;
}
