// Configuration

// Client
export {
  createRedisClient,
  getRedisClient,
  resetRedisClient,
} from "./client.js";
// TCP Config
export {
  type RedisConfig,
  RedisConfigSchema,
  type RedisTCPConfig,
  RedisTCPConfigSchema,
} from "./config.js";
// Hash operations
export { hdel, hget, hgetall, hmset, hset } from "./hash.js";
// Basic KV operations
export type { SetOptions } from "./operations.js";
export {
  del,
  exists,
  expire,
  get,
  mget,
  mset,
  set,
  ttl,
} from "./operations.js";
// Stream operations
export type { StreamMessage, XAddOptions, XReadOptions } from "./streams.js";
export { xadd, xlen, xrange, xread, xrevrange } from "./streams.js";
// TCP Pipelined Streams
export type {
  StreamData,
  XAddOptions as XAddPipelinedOptions,
} from "./streams-pipelined.js";
export { xaddPipelined, xaddSingle } from "./streams-pipelined.js";
// TCP Client
export {
  closeRedisTCPClient,
  createRedisTCPClient,
  getRedisTCPClient,
  resetRedisTCPClient,
} from "./tcp-client.js";
