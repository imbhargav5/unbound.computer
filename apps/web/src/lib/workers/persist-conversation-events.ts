import { createClient } from "@supabase/supabase-js";
import { createRedisClient, xread } from "@unbound/redis";
import type { Database } from "database/types";

/**
 * Environment configuration for the worker
 */
interface WorkerConfig {
  redisToken: string;
  redisUrl: string;
  supabaseServiceKey: string;
  supabaseUrl: string;
}

/**
 * Stream position tracker
 */
interface StreamPosition {
  lastMessageId: string;
  lastProcessedAt: number;
  sessionId: string;
}

/**
 * In-memory state (could be moved to Redis for multi-worker setups)
 */
const streamPositions = new Map<string, StreamPosition>();

/**
 * Get active session IDs from Supabase
 */
async function getActiveSessions(
  supabase: ReturnType<typeof createClient<Database>>
): Promise<string[]> {
  const { data, error } = await supabase
    .from("agent_coding_sessions")
    .select("id")
    .in("status", ["active", "paused"]);

  if (error) {
    console.error("Error fetching active sessions:", error);
    return [];
  }

  return data.map((s) => s.id);
}

/**
 * Redis stream message data structure (from relay /messages endpoint)
 */
interface RedisMessageData {
  contentEncrypted: string; // Base64 encoded
  contentNonce: string; // Base64 encoded
  createdAt: string;
  eventId: string;
  eventType: string;
  messageId: string;
  role: string;
  sequenceNumber: string;
  sessionEventType: string;
}

/**
 * Process encrypted messages from Redis stream and persist to Supabase
 */
async function processSessionStream(
  sessionId: string,
  supabase: ReturnType<typeof createClient<Database>>
): Promise<number> {
  // Read from the unified messages stream (new encrypted format)
  const streamKey = `session:${sessionId}:messages`;

  // Get last processed position or start from beginning
  const position = streamPositions.get(sessionId) || {
    sessionId,
    lastMessageId: "0",
    lastProcessedAt: Date.now(),
  };

  try {
    // Read new messages from stream
    const results = await xread(
      { [streamKey]: position.lastMessageId },
      { count: 100 } // Process in batches of 100
    );

    if (results.length === 0 || results[0].messages.length === 0) {
      return 0; // No new messages
    }

    const messages = results[0].messages;

    // Prepare batch insert for new schema with encrypted content
    // Note: Supabase accepts base64 strings for BYTEA columns
    const messagesToInsert = messages.map((msg) => {
      const data = msg.data as unknown as RedisMessageData;
      return {
        session_id: sessionId,
        sequence_number: Number.parseInt(data.sequenceNumber, 10),
        role: data.role || "assistant",
        // Keep as base64 strings - Supabase handles the conversion
        content_encrypted: data.contentEncrypted || null,
        content_nonce: data.contentNonce || null,
      };
    });

    // Batch insert to Supabase
    const { error: insertError } = await supabase
      .from("agent_coding_session_messages")
      .insert(messagesToInsert);

    if (insertError) {
      console.error(
        `Error inserting messages for session ${sessionId}:`,
        insertError
      );
      return 0;
    }

    // Update position
    const newPosition: StreamPosition = {
      sessionId,
      lastMessageId: messages[messages.length - 1].id,
      lastProcessedAt: Date.now(),
    };
    streamPositions.set(sessionId, newPosition);

    console.log(
      `[Persist Worker] Persisted ${messages.length} messages for session ${sessionId}`
    );

    return messages.length;
  } catch (error) {
    console.error(`Error processing stream for session ${sessionId}:`, error);
    return 0;
  }
}

/**
 * Main worker function (to be called by cron job)
 */
export async function persistConversationEvents(config: WorkerConfig): Promise<{
  sessionsProcessed: number;
  eventsPersistedTotal: number;
}> {
  // Initialize Redis client
  createRedisClient({
    url: config.redisUrl,
    token: config.redisToken,
  });

  // Initialize Supabase client
  const supabase = createClient<Database>(
    config.supabaseUrl,
    config.supabaseServiceKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    }
  );

  // Get active sessions
  const activeSessions = await getActiveSessions(supabase);

  console.log(
    `[Persist Worker] Processing ${activeSessions.length} active sessions`
  );

  // Process each session stream
  let totalProcessed = 0;
  for (const sessionId of activeSessions) {
    const count = await processSessionStream(sessionId, supabase);
    totalProcessed += count;
  }

  // Cleanup old positions (sessions ended > 24h ago)
  const now = Date.now();
  const DAY_MS = 24 * 60 * 60 * 1000;
  for (const [sessionId, position] of streamPositions.entries()) {
    if (now - position.lastProcessedAt > DAY_MS) {
      streamPositions.delete(sessionId);
    }
  }

  console.log(`[Persist Worker] Persisted ${totalProcessed} events`);

  return {
    sessionsProcessed: activeSessions.length,
    eventsPersistedTotal: totalProcessed,
  };
}
