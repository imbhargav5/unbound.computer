import { getRedisClient } from "./client.js";

/**
 * Redis Stream message entry
 */
export interface StreamMessage {
  /** Key-value pairs in the message */
  data: Record<string, string>;
  /** Redis message ID (e.g., "1234567890123-0") */
  id: string;
}

/**
 * Options for XADD operation
 */
export interface XAddOptions {
  /** Approximate trimming (more efficient) */
  approximate?: boolean;
  /** Maximum stream length (MAXLEN ~) */
  maxlen?: number;
}

/**
 * Options for XREAD operation
 */
export interface XReadOptions {
  /** Block for N milliseconds (0 = infinite) */
  block?: number;
  /** Maximum number of messages per stream */
  count?: number;
}

/**
 * Add entry to Redis Stream
 *
 * @param key - Stream key
 * @param data - Message data (key-value pairs)
 * @param options - Optional MAXLEN and trimming
 * @returns Message ID
 *
 * @example
 * ```typescript
 * const id = await xadd("session:123:cvs", {
 *   nonce: "1",
 *   payload: base64EncodedData
 * }, { maxlen: 10000, approximate: true });
 * ```
 */
export async function xadd(
  key: string,
  data: Record<string, string>,
  options?: XAddOptions
): Promise<string> {
  const client = getRedisClient();

  const opts = options?.maxlen
    ? {
        trim: {
          type: "MAXLEN" as const,
          threshold: options.maxlen,
          comparison: options.approximate ? ("~" as const) : ("=" as const),
        },
      }
    : undefined;

  return client.xadd(key, "*", data, opts);
}

/**
 * Read from Redis Streams (blocking or non-blocking)
 *
 * @param streams - Map of stream keys to starting IDs
 * @param options - Blocking and count options
 * @returns Array of stream results
 *
 * @example
 * ```typescript
 * // Non-blocking: read new messages
 * const results = await xread({ "session:123:cvs": "0" }, { count: 100 });
 *
 * // Blocking: wait for new messages
 * const results = await xread(
 *   { "session:123:cvs": "$" },
 *   { block: 5000, count: 10 }
 * );
 * ```
 */
export async function xread(
  streams: Record<string, string>,
  options?: XReadOptions
): Promise<Array<{ stream: string; messages: StreamMessage[] }>> {
  const client = getRedisClient();

  const keys = Object.keys(streams);
  const ids = Object.values(streams);

  const xreadOptions = {
    count: options?.count,
    blockMS: options?.block,
  };

  // Use array form for multiple streams, single form for single stream
  let result: unknown[];
  if (keys.length === 1) {
    result = await client.xread(keys[0], ids[0], xreadOptions);
  } else {
    result = await client.xread(keys, ids, xreadOptions);
  }

  if (!result || result.length === 0) return [];

  // Parse Redis response format
  // Upstash returns an object keyed by stream name
  const parsed = result as Array<
    Record<string, Array<[string, Record<string, string>]>>
  >;

  return parsed.map((streamEntry) => {
    const [streamKey, messages] = Object.entries(streamEntry)[0];
    return {
      stream: streamKey,
      messages: messages.map(([id, fields]) => ({
        id,
        data: fields,
      })),
    };
  });
}

/**
 * Read range of messages from stream
 *
 * @param key - Stream key
 * @param start - Start ID (or "-" for beginning)
 * @param end - End ID (or "+" for end)
 * @param count - Optional max number of messages
 * @returns Array of messages
 *
 * @example
 * ```typescript
 * // Get all messages
 * const all = await xrange("session:123:cvs", "-", "+");
 *
 * // Get last 100 messages
 * const recent = await xrange("session:123:cvs", "-", "+", 100);
 * ```
 */
export async function xrange(
  key: string,
  start: string,
  end: string,
  count?: number
): Promise<StreamMessage[]> {
  const client = getRedisClient();

  const result = await client.xrange(key, start, end, count);

  // Upstash returns Record<string, Record<string, unknown>>
  // where keys are message IDs and values are the field data
  return Object.entries(result).map(([id, fields]) => ({
    id,
    data: fields as Record<string, string>,
  }));
}

/**
 * Read range in reverse order
 *
 * @param key - Stream key
 * @param start - Start ID (or "+" for end)
 * @param end - End ID (or "-" for beginning)
 * @param count - Optional max number of messages
 * @returns Array of messages in reverse order
 *
 * @example
 * ```typescript
 * // Get last 100 messages
 * const recent = await xrevrange("session:123:cvs", "+", "-", 100);
 * ```
 */
export async function xrevrange(
  key: string,
  start: string,
  end: string,
  count?: number
): Promise<StreamMessage[]> {
  const client = getRedisClient();

  // Note: upstash xrevrange signature is (key, end, start, count)
  const result = await client.xrevrange(key, start, end, count);

  // Upstash returns Record<string, Record<string, unknown>>
  return Object.entries(result).map(([id, fields]) => ({
    id,
    data: fields as Record<string, string>,
  }));
}

/**
 * Get stream length
 *
 * @param key - Stream key
 * @returns Number of entries in the stream
 *
 * @example
 * ```typescript
 * const length = await xlen("session:123:cvs");
 * ```
 */
export async function xlen(key: string): Promise<number> {
  const client = getRedisClient();
  return client.xlen(key);
}
