import type { ChainableCommander } from "ioredis";
import { getRedisTCPClient } from "./tcp-client.js";

/**
 * Options for XADD with MAXLEN trimming
 */
export interface XAddOptions {
  /** Maximum stream length */
  maxlen?: number;
  /** Use approximate trimming (~) for better performance */
  approximate?: boolean;
}

/**
 * Data to add to a Redis stream
 */
export interface StreamData {
  [key: string]: string | number;
}

/**
 * Add multiple events to a Redis stream using pipelining.
 * This ensures all events are sent over a single TCP connection
 * and arrive in Redis in the exact order they're provided.
 *
 * Uses Redis pipelining to batch multiple XADD commands into a single
 * network round-trip, dramatically improving performance while maintaining
 * strict ordering guarantees.
 *
 * @param streamKey - Redis stream key (e.g., "session:uuid:cvs")
 * @param events - Array of events to add in order
 * @param options - Optional MAXLEN trimming configuration
 * @returns Array of Redis stream message IDs in order
 *
 * @example
 * ```typescript
 * const ids = await xaddPipelined(
 *   'session:123:cvs',
 *   [
 *     { eventId: '1', type: 'USER_PROMPT', payload: '{"text":"hello"}' },
 *     { eventId: '2', type: 'OUTPUT_CHUNK', payload: '{"text":"hi"}' },
 *   ],
 *   { maxlen: 10000, approximate: true }
 * );
 * // ids = ['1737330000000-0', '1737330000000-1']
 * ```
 */
export async function xaddPipelined(
  streamKey: string,
  events: StreamData[],
  options: XAddOptions = {}
): Promise<string[]> {
  const redis = getRedisTCPClient();
  const pipeline = redis.pipeline();

  // Add all XADD commands to the pipeline
  for (const event of events) {
    addXaddToPipeline(pipeline, streamKey, event, options);
  }

  // Execute pipeline atomically
  const results = await pipeline.exec();

  if (!results) {
    throw new Error("Pipeline execution returned null");
  }

  // Extract stream message IDs, filtering out errors
  const messageIds: string[] = [];
  for (const [error, result] of results) {
    if (error) {
      throw error;
    }
    messageIds.push(result as string);
  }

  return messageIds;
}

/**
 * Add a single XADD command to a Redis pipeline.
 * Handles MAXLEN trimming if specified in options.
 *
 * @param pipeline - ioredis pipeline instance
 * @param streamKey - Redis stream key
 * @param data - Event data as key-value pairs
 * @param options - MAXLEN options
 */
function addXaddToPipeline(
  pipeline: ChainableCommander,
  streamKey: string,
  data: StreamData,
  options: XAddOptions
): void {
  const args: (string | number)[] = [streamKey];

  // Add MAXLEN if specified
  if (options.maxlen !== undefined) {
    if (options.approximate) {
      args.push("MAXLEN", "~", options.maxlen);
    } else {
      args.push("MAXLEN", options.maxlen);
    }
  }

  // Add auto-generated ID (*)
  args.push("*");

  // Add data as field-value pairs
  for (const [field, value] of Object.entries(data)) {
    args.push(field, value.toString());
  }

  // Add to pipeline
  pipeline.xadd(streamKey, ...args.slice(1));
}

/**
 * Add a single event to a Redis stream.
 * For single events, this is more efficient than pipelining.
 * For multiple events, use xaddPipelined() to maintain ordering.
 *
 * @param streamKey - Redis stream key
 * @param data - Event data as key-value pairs
 * @param options - MAXLEN options
 * @returns Redis stream message ID
 *
 * @example
 * ```typescript
 * const id = await xaddSingle(
 *   'session:123:cvs',
 *   { eventId: '1', type: 'USER_PROMPT', payload: '{"text":"hello"}' },
 *   { maxlen: 10000, approximate: true }
 * );
 * // id = '1737330000000-0'
 * ```
 */
export async function xaddSingle(
  streamKey: string,
  data: StreamData,
  options: XAddOptions = {}
): Promise<string> {
  const redis = getRedisTCPClient();
  const args: (string | number)[] = [streamKey];

  // Add MAXLEN if specified
  if (options.maxlen !== undefined) {
    if (options.approximate) {
      args.push("MAXLEN", "~", options.maxlen);
    } else {
      args.push("MAXLEN", options.maxlen);
    }
  }

  // Add auto-generated ID (*)
  args.push("*");

  // Add data as field-value pairs
  for (const [field, value] of Object.entries(data)) {
    args.push(field, value.toString());
  }

  // Execute XADD
  const messageId = await redis.xadd(streamKey, ...args.slice(1));
  if (!messageId) {
    throw new Error("XADD returned null");
  }
  return messageId;
}
