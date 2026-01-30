import { xread } from "@unbound/redis";
import { config } from "../config.js";
import { createLogger } from "../utils/index.js";
import { connectionManager } from "./connection-manager.js";

const log = createLogger({ module: "stream-subscriber" });

/**
 * Stream types for Redis pub/sub
 */
type StreamType = "cvs" | "communication";

/**
 * Stream position tracker
 */
interface StreamPosition {
  sessionId: string;
  streamType: StreamType;
  lastMessageId: string;
  subscriberCount: number;
}

/**
 * Generate stream key from session ID and stream type
 */
function getStreamKey(sessionId: string, streamType: StreamType): string {
  return `session:${sessionId}:${streamType}`;
}

/**
 * Parse stream key to extract session ID and stream type
 */
function parseStreamKey(
  streamKey: string
): { sessionId: string; streamType: StreamType } | null {
  const parts = streamKey.split(":");
  if (parts.length !== 3 || parts[0] !== "session") {
    return null;
  }
  const streamType = parts[2] as StreamType;
  if (streamType !== "cvs" && streamType !== "communication") {
    return null;
  }
  return { sessionId: parts[1], streamType };
}

/**
 * Manages Redis stream subscriptions for active sessions
 * Subscribes to both conversation (cvs) and communication streams per session
 */
class StreamSubscriberManager {
  // Key format: "session:{sessionId}:{streamType}"
  private positions = new Map<string, StreamPosition>();
  private pollInterval: NodeJS.Timeout | null = null;
  private isRunning = false;

  /**
   * Start the polling loop
   */
  start(): void {
    if (this.isRunning) {
      log.warn("Stream subscriber already running");
      return;
    }

    this.isRunning = true;
    log.info(
      {
        intervalMs: config.STREAM_POLL_INTERVAL_MS,
        batchSize: config.STREAM_BATCH_SIZE,
        maxStreamLen: config.STREAM_MAX_LEN,
      },
      "Starting Redis stream subscriber - polling for conversation events"
    );

    this.pollInterval = setInterval(() => {
      this.pollStreams().catch((error) => {
        log.error({ error }, "Error polling Redis streams");
      });
    }, config.STREAM_POLL_INTERVAL_MS);
  }

  /**
   * Stop the polling loop
   */
  stop(): void {
    if (!this.isRunning) {
      return;
    }

    this.isRunning = false;
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }

    log.info("Stopped stream subscriber");
  }

  /**
   * Subscribe a session to Redis stream updates
   * Subscribes to both conversation (cvs) and communication streams
   */
  subscribe(sessionId: string): void {
    const streamTypes: StreamType[] = ["cvs", "communication"];

    for (const streamType of streamTypes) {
      const streamKey = getStreamKey(sessionId, streamType);
      const existing = this.positions.get(streamKey);

      if (existing) {
        existing.subscriberCount++;
        log.debug(
          { sessionId, streamType, subscriberCount: existing.subscriberCount },
          "Added subscriber to existing session stream"
        );
      } else {
        this.positions.set(streamKey, {
          sessionId,
          streamType,
          lastMessageId: "$", // Only new messages
          subscriberCount: 1,
        });
        log.info(
          {
            sessionId,
            streamType,
            streamKey,
            startPosition: "$",
          },
          "New session subscribed to Redis stream - will receive new events only"
        );
      }
    }
  }

  /**
   * Unsubscribe a session from all its streams
   */
  unsubscribe(sessionId: string): void {
    const streamTypes: StreamType[] = ["cvs", "communication"];

    for (const streamType of streamTypes) {
      const streamKey = getStreamKey(sessionId, streamType);
      const existing = this.positions.get(streamKey);

      if (!existing) {
        log.debug(
          { sessionId, streamType },
          "Attempted to unsubscribe non-existent session stream"
        );
        continue;
      }

      existing.subscriberCount--;

      if (existing.subscriberCount <= 0) {
        this.positions.delete(streamKey);
        log.info(
          { sessionId, streamType, streamKey },
          "Session fully unsubscribed from Redis stream - no more subscribers"
        );
      } else {
        log.debug(
          {
            sessionId,
            streamType,
            remainingSubscribers: existing.subscriberCount,
          },
          "Removed subscriber from session stream"
        );
      }
    }
  }

  /**
   * Poll all active streams
   */
  private async pollStreams(): Promise<void> {
    if (this.positions.size === 0) {
      return;
    }

    // Build streams object for XREAD (includes both cvs and communication streams)
    const streams: Record<string, string> = {};
    for (const [streamKey, position] of this.positions.entries()) {
      streams[streamKey] = position.lastMessageId;
    }

    const streamCount = Object.keys(streams).length;
    const pollStartTime = Date.now();

    try {
      // Read from all streams (non-blocking)
      const results = await xread(streams, {
        count: config.STREAM_BATCH_SIZE,
        block: 0, // Non-blocking
      });

      const pollDuration = Date.now() - pollStartTime;

      if (results.length === 0) {
        // Only log at trace level to avoid noise - but use debug for now
        log.debug(
          { streamCount, pollDurationMs: pollDuration },
          "Redis XREAD returned no new messages"
        );
        return;
      }

      log.debug(
        {
          streamCount,
          streamsWithMessages: results.length,
          pollDurationMs: pollDuration,
        },
        "Redis XREAD returned messages from streams"
      );

      // Process results
      for (const { stream, messages } of results) {
        // Parse stream key to extract session ID and stream type
        const parsed = parseStreamKey(stream);
        if (!parsed || messages.length === 0) {
          continue;
        }

        const { sessionId, streamType } = parsed;
        const oldPosition = this.positions.get(stream)?.lastMessageId;

        // Update position
        const position = this.positions.get(stream);
        if (position) {
          position.lastMessageId = messages[messages.length - 1].id;
        }

        log.debug(
          {
            sessionId,
            streamType,
            streamKey: stream,
            messageCount: messages.length,
            oldPosition,
            newPosition: position?.lastMessageId,
          },
          "Processing messages from Redis stream"
        );

        // Forward messages to connected devices
        this.forwardMessagesToSession(sessionId, streamType, messages);
      }
    } catch (error) {
      const pollDuration = Date.now() - pollStartTime;
      log.error(
        {
          error,
          streamCount,
          pollDurationMs: pollDuration,
          streamKeys: Object.keys(streams),
        },
        "Error reading from Redis streams - XREAD failed"
      );
    }
  }

  /**
   * Forward messages to all session members via WebSocket
   */
  private forwardMessagesToSession(
    sessionId: string,
    streamType: StreamType,
    messages: Array<{
      id: string;
      data: Record<string, string>;
    }>
  ): void {
    const members = connectionManager.getSessionMembers(sessionId);

    if (members.length === 0) {
      log.debug(
        { sessionId, streamType, messageCount: messages.length },
        "No connected members for session - skipping message forward"
      );
      return;
    }

    // Determine event type based on stream type
    const eventType =
      streamType === "communication"
        ? "COMMUNICATION_EVENT"
        : "CONVERSATION_EVENT";

    // Format messages as relay events
    for (const msg of messages) {
      const event = {
        type: eventType,
        sessionId,
        streamId: msg.id,
        eventId: msg.data.eventId,
        eventType: msg.data.type,
        payload: JSON.parse(msg.data.payload),
        createdAt: Number.parseInt(msg.data.createdAt, 10),
      };

      const serialized = JSON.stringify(event);

      // Broadcast to all session members
      const sentCount = connectionManager.broadcastToSession(
        sessionId,
        serialized
      );

      log.debug(
        {
          sessionId,
          streamType,
          streamId: msg.id,
          eventId: msg.data.eventId,
          eventType: msg.data.type,
          memberCount: members.length,
          sentCount,
        },
        "Forwarded event to session members"
      );
    }

    log.info(
      {
        sessionId,
        streamType,
        eventCount: messages.length,
        memberCount: members.length,
        eventTypes: messages.map((m) => m.data.type),
      },
      "Forwarded events from Redis to WebSocket clients"
    );
  }

  /**
   * Get current subscription count
   */
  getActiveSessionCount(): number {
    return this.positions.size;
  }

  /**
   * Get stats for monitoring
   */
  getStats(): {
    activeSessions: number;
    totalSubscribers: number;
  } {
    let totalSubscribers = 0;
    for (const position of this.positions.values()) {
      totalSubscribers += position.subscriberCount;
    }

    return {
      activeSessions: this.positions.size,
      totalSubscribers,
    };
  }
}

export const streamSubscriber = new StreamSubscriberManager();
