import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import { connectionManager, presenceManager } from "../managers/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "http-server" });

/**
 * Create HTTP server with health check endpoints
 */
export function createHttpServer(): Server {
  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
    // Health check endpoint - basic liveness
    if (req.url === "/health" && req.method === "GET") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          status: "ok",
          timestamp: Date.now(),
        })
      );
      return;
    }

    // Ready check endpoint - includes connection stats
    if (req.url === "/ready" && req.method === "GET") {
      const connectionStats = connectionManager.getStats();
      const presenceStats = presenceManager.getStats();

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          status: "ready",
          timestamp: Date.now(),
          connections: {
            total: connectionStats.totalConnections,
            authenticated: connectionStats.authenticatedConnections,
          },
          sessions: {
            active: connectionStats.totalSessions,
          },
          presence: {
            online: presenceStats.totalOnline,
            away: presenceStats.totalAway,
          },
        })
      );
      return;
    }

    // 404 for other routes
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  });

  server.on("error", (error) => {
    log.error({ error }, "HTTP server error");
  });

  return server;
}
