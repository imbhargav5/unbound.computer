import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import { createRedisClient, xadd } from "@unbound/redis";
import { SessionEvent, UlidSchema } from "@unbound/transport-reliability";
import { z } from "zod";
import { config } from "../config.js";
import { connectionManager, presenceManager } from "../managers/index.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "http-server" });

/**
 * Remote command event types - commands sent FROM remotes (iOS/web) TO executor
 * These go to session:{sessionId}:remote_commands stream
 */
const REMOTE_COMMAND_EVENT_TYPES = new Set([
  "SESSION_PAUSE_COMMAND",
  "SESSION_RESUME_COMMAND",
  "SESSION_STOP_COMMAND",
  "SESSION_CANCEL_COMMAND",
  "USER_PROMPT_COMMAND",
  "USER_CONFIRMATION_COMMAND",
  "MCQ_RESPONSE_COMMAND",
  "TOOL_APPROVAL_COMMAND",
  "WORKTREE_CREATE_COMMAND",
  "CONFLICTS_FIX_COMMAND",
]);

/**
 * Executor update event types - state updates sent FROM executor TO remotes
 * These go to session:{sessionId}:executor_updates stream
 */
const EXECUTOR_UPDATE_EVENT_TYPES = new Set([
  "QUESTION_ASKED",
  "QUESTION_ANSWERED",
  "TOOL_APPROVAL_REQUIRED",
  "EXECUTION_STARTED",
  "EXECUTION_COMPLETED",
  "SESSION_STATE_CHANGED",
  "SESSION_ERROR",
  "SESSION_WARNING",
  "RATE_LIMIT_WARNING",
  "SESSION_HEARTBEAT",
  "CONNECTION_QUALITY_UPDATE",
]);

/**
 * Conversation message event types - streaming content and file changes
 * These go to session:{sessionId}:messages stream
 */
const MESSAGE_EVENT_TYPES = new Set([
  "OUTPUT_CHUNK",
  "STREAMING_THINKING",
  "STREAMING_GENERATING",
  "STREAMING_WAITING",
  "STREAMING_IDLE",
  "TOOL_STARTED",
  "TOOL_OUTPUT_CHUNK",
  "TOOL_COMPLETED",
  "TOOL_FAILED",
  "FILE_CREATED",
  "FILE_MODIFIED",
  "FILE_DELETED",
  "FILE_RENAMED",
  "TODO_LIST_UPDATED",
  "TODO_ITEM_UPDATED",
]);

/**
 * Flexible session ID schema that accepts both UUID and ULID formats
 * (existing sessions may use UUID format, new ones use ULID)
 */
const SessionIdSchema = z.string().min(1);

/**
 * Request body for event ingestion
 */
const EventsRequestSchema = z.object({
  sessionId: SessionIdSchema,
  deviceToken: z.string(),
  batchId: UlidSchema,
  events: z.array(SessionEvent),
});

/**
 * Initialize Redis client for event streaming
 */
function initializeRedis() {
  const redisUrl = config.UPSTASH_REDIS_REST_URL;
  // Mask the URL for logging (show host only)
  const maskedUrl = new URL(redisUrl).host;

  log.debug({ redisHost: maskedUrl }, "Initializing Redis client connection");

  try {
    createRedisClient({
      UPSTASH_REDIS_REST_URL: config.UPSTASH_REDIS_REST_URL,
      UPSTASH_REDIS_REST_TOKEN: config.UPSTASH_REDIS_REST_TOKEN,
    });
    log.info(
      { redisHost: maskedUrl },
      "Redis client initialized successfully for event streaming"
    );
  } catch (error) {
    log.error(
      { error, redisHost: maskedUrl },
      "Failed to initialize Redis client"
    );
    throw error;
  }
}

/**
 * Handle POST /events - ingest conversation events from macOS
 */
async function handleEventIngestion(
  body: string
): Promise<{ status: number; data: unknown }> {
  const ingestionStartTime = Date.now();

  try {
    const rawBody = JSON.parse(body);
    const parsed = EventsRequestSchema.safeParse(rawBody);

    if (!parsed.success) {
      log.warn(
        {
          issues: parsed.error.issues,
          sessionId: rawBody?.sessionId,
          batchId: rawBody?.batchId,
          eventCount: rawBody?.events?.length,
          eventTypes: rawBody?.events?.map((e: { type?: string }) => e.type),
          sampleEvent: rawBody?.events?.[0],
        },
        "Event validation failed"
      );
      return {
        status: 400,
        data: { error: "Invalid request body", details: parsed.error.issues },
      };
    }

    const { sessionId, deviceToken, batchId, events } = parsed.data;

    log.debug(
      {
        sessionId,
        batchId,
        totalEvents: events.length,
        eventTypes: events.map((e) => e.type),
      },
      "Processing event batch from macOS client"
    );

    // TODO: Verify device token matches the session's executor device
    // For now, we trust the device token from the client

    // Categorize events by type
    const messageEvents = events.filter((event) =>
      MESSAGE_EVENT_TYPES.has(event.type)
    );
    const remoteCommandEvents = events.filter((event) =>
      REMOTE_COMMAND_EVENT_TYPES.has(event.type)
    );
    const executorUpdateEvents = events.filter((event) =>
      EXECUTOR_UPDATE_EVENT_TYPES.has(event.type)
    );

    const totalStreamableEvents =
      messageEvents.length +
      remoteCommandEvents.length +
      executorUpdateEvents.length;

    if (totalStreamableEvents === 0) {
      log.debug(
        {
          sessionId,
          batchId,
          totalEvents: events.length,
          filteredOut: events.map((e) => e.type),
        },
        "No events to stream - all events filtered out"
      );
      return {
        status: 200,
        data: {
          success: true,
          batchId,
          sessionId,
          message: "No events to stream",
          totalEvents: events.length,
          conversationMessages: 0,
          remoteCommands: 0,
          executorUpdates: 0,
          streamedIds: 0,
          timestamp: Date.now(),
        },
      };
    }

    // Stream keys
    const messagesStreamKey = `session:${sessionId}:messages`;
    const remoteCommandsStreamKey = `session:${sessionId}:remote_commands`;
    const executorUpdatesStreamKey = `session:${sessionId}:executor_updates`;

    const addedIds: {
      messages: string[];
      remoteCommands: string[];
      executorUpdates: string[];
    } = {
      messages: [],
      remoteCommands: [],
      executorUpdates: [],
    };
    const redisStartTime = Date.now();

    log.debug(
      {
        sessionId,
        messagesStreamKey,
        remoteCommandsStreamKey,
        executorUpdatesStreamKey,
        messageCount: messageEvents.length,
        remoteCommandCount: remoteCommandEvents.length,
        executorUpdateCount: executorUpdateEvents.length,
      },
      "Streaming events to Redis"
    );

    // Stream conversation messages
    for (const event of messageEvents) {
      const messageId = await xadd(
        messagesStreamKey,
        {
          eventId: event.eventId,
          type: event.type,
          payload: JSON.stringify(event),
          createdAt: event.createdAt.toString(),
        },
        {
          maxlen: config.STREAM_MAX_LEN,
          approximate: true,
        }
      );
      addedIds.messages.push(messageId);
    }

    // Stream remote commands
    for (const event of remoteCommandEvents) {
      const messageId = await xadd(
        remoteCommandsStreamKey,
        {
          eventId: event.eventId,
          type: event.type,
          payload: JSON.stringify(event),
          createdAt: event.createdAt.toString(),
        },
        {
          maxlen: config.STREAM_MAX_LEN,
          approximate: true,
        }
      );
      addedIds.remoteCommands.push(messageId);
    }

    // Stream executor updates
    for (const event of executorUpdateEvents) {
      const messageId = await xadd(
        executorUpdatesStreamKey,
        {
          eventId: event.eventId,
          type: event.type,
          payload: JSON.stringify(event),
          createdAt: event.createdAt.toString(),
        },
        {
          maxlen: config.STREAM_MAX_LEN,
          approximate: true,
        }
      );
      addedIds.executorUpdates.push(messageId);
    }

    const redisDuration = Date.now() - redisStartTime;
    const totalDuration = Date.now() - ingestionStartTime;

    const totalStreamed =
      addedIds.messages.length +
      addedIds.remoteCommands.length +
      addedIds.executorUpdates.length;

    log.info(
      {
        sessionId,
        batchId,
        totalEvents: events.length,
        conversationMessages: messageEvents.length,
        remoteCommands: remoteCommandEvents.length,
        executorUpdates: executorUpdateEvents.length,
        messagesStreamKey,
        remoteCommandsStreamKey,
        executorUpdatesStreamKey,
        redisDurationMs: redisDuration,
        totalDurationMs: totalDuration,
      },
      "Events streamed to Redis successfully"
    );

    return {
      status: 200,
      data: {
        success: true,
        batchId,
        message: "Events streamed successfully",
        sessionId,
        totalEvents: events.length,
        conversationMessages: messageEvents.length,
        remoteCommands: remoteCommandEvents.length,
        executorUpdates: executorUpdateEvents.length,
        streamedIds: totalStreamed,
        timestamp: Date.now(),
      },
    };
  } catch (error) {
    const totalDuration = Date.now() - ingestionStartTime;
    log.error(
      { error, durationMs: totalDuration },
      "Error ingesting events - Redis write may have failed"
    );
    return {
      status: 500,
      data: { error: "Internal server error" },
    };
  }
}

/**
 * Handle POST /messages - ingest encrypted session messages from macOS
 * Routes to three streams based on event type:
 * - session:{sessionId}:messages - conversation content (OUTPUT_CHUNK, TOOL_*, FILE_*, etc.)
 * - session:{sessionId}:remote_commands - commands from remotes to executor
 * - session:{sessionId}:executor_updates - state updates from executor to remotes
 */
async function handleMessageIngestion(
  body: string
): Promise<{ status: number; data: unknown }> {
  const ingestionStartTime = Date.now();

  try {
    const rawBody = JSON.parse(body);

    const SessionMessagesRequestSchema = z.object({
      sessionId: z.string().min(1),
      deviceToken: z.string(),
      batchId: UlidSchema,
      messages: z.array(
        z.object({
          eventId: z.string(),
          sessionId: z.string().min(1),
          messageId: z.string(),
          role: z.enum(["user", "assistant", "system"]),
          sequenceNumber: z.number().int().nonnegative(),
          createdAt: z.number(),
          contentEncrypted: z.string(), // Base64 encoded
          contentNonce: z.string(), // Base64 encoded
          sessionEventType: z.enum([
            "REMOTE_COMMAND",
            "EXECUTOR_UPDATE",
            "LOCAL_EXECUTION_COMMAND",
          ]),
          eventType: z.string().optional(),
        })
      ),
    });

    const parsed = SessionMessagesRequestSchema.safeParse(rawBody);

    if (!parsed.success) {
      log.warn(
        {
          issues: parsed.error.issues,
          sessionId: rawBody?.sessionId,
          batchId: rawBody?.batchId,
          messageCount: rawBody?.messages?.length,
        },
        "Message validation failed"
      );
      return {
        status: 400,
        data: { error: "Invalid request body", details: parsed.error.issues },
      };
    }

    const { sessionId, batchId, messages } = parsed.data;

    log.debug(
      {
        sessionId,
        batchId,
        totalMessages: messages.length,
        roles: messages.map((m) => m.role),
        eventTypes: messages.map((m) => m.eventType),
      },
      "Processing encrypted message batch from macOS client"
    );

    // Categorize messages by event type
    const conversationMsgs = messages.filter(
      (msg) => msg.eventType && MESSAGE_EVENT_TYPES.has(msg.eventType)
    );
    const remoteCommandMsgs = messages.filter(
      (msg) => msg.eventType && REMOTE_COMMAND_EVENT_TYPES.has(msg.eventType)
    );
    const executorUpdateMsgs = messages.filter(
      (msg) => msg.eventType && EXECUTOR_UPDATE_EVENT_TYPES.has(msg.eventType)
    );

    // Stream keys
    const messagesStreamKey = `session:${sessionId}:messages`;
    const remoteCommandsStreamKey = `session:${sessionId}:remote_commands`;
    const executorUpdatesStreamKey = `session:${sessionId}:executor_updates`;

    const addedIds: {
      messages: string[];
      remoteCommands: string[];
      executorUpdates: string[];
    } = {
      messages: [],
      remoteCommands: [],
      executorUpdates: [],
    };
    const redisStartTime = Date.now();

    // Helper to add message to stream
    const addToStream = async (streamKey: string, msg: (typeof messages)[0]) =>
      await xadd(
        streamKey,
        {
          eventId: msg.eventId,
          messageId: msg.messageId,
          role: msg.role,
          sequenceNumber: msg.sequenceNumber.toString(),
          contentEncrypted: msg.contentEncrypted,
          contentNonce: msg.contentNonce,
          eventType: msg.eventType ?? "",
          sessionEventType: msg.sessionEventType,
          createdAt: msg.createdAt.toString(),
        },
        {
          maxlen: config.STREAM_MAX_LEN,
          approximate: true,
        }
      );

    // Stream conversation messages
    for (const msg of conversationMsgs) {
      const id = await addToStream(messagesStreamKey, msg);
      addedIds.messages.push(id);
    }

    // Stream remote commands
    for (const msg of remoteCommandMsgs) {
      const id = await addToStream(remoteCommandsStreamKey, msg);
      addedIds.remoteCommands.push(id);
    }

    // Stream executor updates
    for (const msg of executorUpdateMsgs) {
      const id = await addToStream(executorUpdatesStreamKey, msg);
      addedIds.executorUpdates.push(id);
    }

    const redisDuration = Date.now() - redisStartTime;
    const totalDuration = Date.now() - ingestionStartTime;

    const totalStreamed =
      addedIds.messages.length +
      addedIds.remoteCommands.length +
      addedIds.executorUpdates.length;

    log.info(
      {
        sessionId,
        batchId,
        totalMessages: messages.length,
        conversationMessages: conversationMsgs.length,
        remoteCommands: remoteCommandMsgs.length,
        executorUpdates: executorUpdateMsgs.length,
        messagesStreamKey,
        remoteCommandsStreamKey,
        executorUpdatesStreamKey,
        redisDurationMs: redisDuration,
        totalDurationMs: totalDuration,
      },
      "Encrypted messages streamed to Redis successfully"
    );

    return {
      status: 200,
      data: {
        success: true,
        batchId,
        message: "Messages streamed successfully",
        sessionId,
        totalMessages: messages.length,
        conversationMessages: conversationMsgs.length,
        remoteCommands: remoteCommandMsgs.length,
        executorUpdates: executorUpdateMsgs.length,
        streamedIds: totalStreamed,
        timestamp: Date.now(),
      },
    };
  } catch (error) {
    const totalDuration = Date.now() - ingestionStartTime;
    log.error(
      { error, durationMs: totalDuration },
      "Error ingesting messages - Redis write may have failed"
    );
    return {
      status: 500,
      data: { error: "Internal server error" },
    };
  }
}

/**
 * Read request body as string
 */
function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk.toString();
    });
    req.on("end", () => {
      resolve(body);
    });
    req.on("error", (error) => {
      reject(error);
    });
  });
}

/**
 * Create HTTP server with health check endpoints and event ingestion
 */
export function createHttpServer(): Server {
  // Initialize Redis client on server creation
  initializeRedis();

  const server = createServer(
    async (req: IncomingMessage, res: ServerResponse) => {
      // Enable CORS
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");

      if (req.method === "OPTIONS") {
        res.writeHead(200);
        res.end();
        return;
      }

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

      // Event ingestion endpoint (legacy - unencrypted)
      if (req.url === "/events" && req.method === "POST") {
        try {
          const body = await readBody(req);
          const result = await handleEventIngestion(body);
          res.writeHead(result.status, { "Content-Type": "application/json" });
          res.end(JSON.stringify(result.data));
        } catch (error) {
          log.error({ error }, "Error handling /events request");
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Internal server error" }));
        }
        return;
      }

      // Message ingestion endpoint (new - encrypted)
      if (req.url === "/messages" && req.method === "POST") {
        try {
          const body = await readBody(req);
          const result = await handleMessageIngestion(body);
          res.writeHead(result.status, { "Content-Type": "application/json" });
          res.end(JSON.stringify(result.data));
        } catch (error) {
          log.error({ error }, "Error handling /messages request");
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Internal server error" }));
        }
        return;
      }

      // 404 for other routes
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Not found" }));
    }
  );

  server.on("error", (error) => {
    log.error({ error }, "HTTP server error");
  });

  return server;
}
