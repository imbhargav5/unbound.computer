import { config } from "./config.js";
import { presenceManager, streamSubscriber } from "./managers/index.js";
import { createHttpServer, createWebSocketServer } from "./server/index.js";
import { notificationManager } from "./services/index.js";
import { logger } from "./utils/index.js";

const log = logger.child({ module: "main" });

/**
 * Graceful shutdown handler
 */
function setupGracefulShutdown(
  httpServer: ReturnType<typeof createHttpServer>
): void {
  const shutdown = (signal: string) => {
    log.info({ signal }, "Shutdown signal received");

    // Stop presence manager
    presenceManager.stop();

    // Stop stream subscriber
    streamSubscriber.stop();

    // Shutdown notification manager (closes HTTP/2 sessions)
    notificationManager.shutdown();

    // Close HTTP server (and WebSocket server)
    httpServer.close(() => {
      log.info("Server closed");
      process.exit(0);
    });

    // Force exit after 10 seconds
    setTimeout(() => {
      log.warn("Forcing shutdown");
      process.exit(1);
    }, 10_000);
  };

  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

/**
 * Start the relay server
 */
async function main(): Promise<void> {
  log.info(
    {
      port: config.PORT,
      host: config.HOST,
      env: config.NODE_ENV,
    },
    "Starting relay server"
  );

  // Create HTTP server
  const httpServer = createHttpServer();

  // Attach WebSocket server
  createWebSocketServer(httpServer);

  // Start presence manager
  presenceManager.start();

  // Start stream subscriber for conversation events
  streamSubscriber.start();

  // Initialize notification manager (APNs)
  const notificationsEnabled = notificationManager.initialize();
  log.info(
    { notificationsEnabled },
    notificationsEnabled
      ? "Push notifications enabled"
      : "Push notifications disabled (APNs not configured)"
  );

  // Setup graceful shutdown
  setupGracefulShutdown(httpServer);

  // Start listening
  httpServer.listen(config.PORT, config.HOST, () => {
    log.info(
      { url: `http://${config.HOST}:${config.PORT}` },
      "Relay server listening"
    );
  });
}

// Run
main().catch((error) => {
  log.fatal({ error }, "Failed to start server");
  process.exit(1);
});
