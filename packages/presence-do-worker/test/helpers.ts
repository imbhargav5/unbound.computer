import { createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import * as ts from "typescript";
import { expect } from "vitest";

export const signingKey = "presence-signing-test";
export const ingestToken = "presence-ingest-test";

export const defaultUserId = "123e4567-e89b-12d3-a456-426614174000";
export const defaultDeviceId = "123e4567-e89b-12d3-a456-426614174001";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.resolve(__dirname, "../src/index.ts");
const transpiledScript = ts.transpileModule(readFileSync(scriptPath, "utf8"), {
  compilerOptions: {
    module: ts.ModuleKind.ESNext,
    target: ts.ScriptTarget.ES2022,
  },
}).outputText;

export type PresenceStatus = "online" | "offline";

export type HeartbeatPayload = {
  schema_version: number;
  user_id: string;
  device_id: string;
  status: PresenceStatus;
  source: string;
  sent_at_ms: number;
  seq: number;
  ttl_ms: number;
};

export type DebugState = {
  active_streams: number;
  alarm: string | null;
  records: Record<
    string,
    HeartbeatPayload & {
      last_heartbeat_ms: number;
      last_offline_ms: number | null;
      updated_at_ms: number;
    }
  >;
  cache_loaded: boolean;
  dirty_devices: string[];
  next_flush_ms: number | null;
  next_expiry_ms: number | null;
  next_alarm_ms: number | null;
  stats: {
    storage_puts_total: number;
    set_alarm_total: number;
    delete_alarm_total: number;
    list_records_total: number;
  };
};

function base64UrlEncode(input: string | Buffer) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=+$/, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

export function createPresenceToken(
  payload: Record<string, unknown>,
  options?: { signingKey?: string }
) {
  const key = options?.signingKey ?? signingKey;
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signature = base64UrlEncode(
    createHmac("sha256", key).update(encodedPayload).digest()
  );
  return `${encodedPayload}.${signature}`;
}

export async function createPersistPath(prefix = "presence-do-worker-") {
  return mkdtemp(path.join(tmpdir(), prefix));
}

export function createMiniflare(options?: {
  environment?: "development" | "production";
  keepAliveFlushMs?: number;
  durableObjectsPersist?: string | boolean;
}) {
  const bindings: Record<string, string> = {
    PRESENCE_DO_TOKEN_SIGNING_KEY: signingKey,
    PRESENCE_DO_INGEST_TOKEN: ingestToken,
    ENVIRONMENT: options?.environment ?? "development",
  };

  if (options?.keepAliveFlushMs !== undefined) {
    bindings.PRESENCE_DO_KEEPALIVE_FLUSH_MS = String(options.keepAliveFlushMs);
  }

  return new Miniflare({
    script: transpiledScript,
    scriptPath,
    modules: true,
    compatibilityDate: "2025-02-01",
    durableObjects: { PRESENCE_DO: "PresenceDurableObject" },
    durableObjectsPersist: options?.durableObjectsPersist,
    bindings,
  });
}

export async function disposeMiniflare(mf: Miniflare | undefined) {
  if (!mf) return;
  await mf.dispose();
}

export function makeHeartbeat(
  overrides: Partial<HeartbeatPayload> = {}
): HeartbeatPayload {
  return {
    schema_version: 1,
    user_id: defaultUserId,
    device_id: defaultDeviceId,
    status: "online",
    source: "daemon-do",
    sent_at_ms: Date.now(),
    seq: 1,
    ttl_ms: 12_000,
    ...overrides,
  };
}

export async function dispatchHeartbeat(
  mf: Miniflare,
  payload: HeartbeatPayload,
  options?: { token?: string; rawBody?: string; headers?: HeadersInit }
) {
  const headers: HeadersInit = {
    "Content-Type": "application/json",
    ...(options?.headers ?? {}),
  };

  const token = options?.token ?? ingestToken;
  if (token) {
    (headers as Record<string, string>).Authorization = `Bearer ${token}`;
  }

  return mf.dispatchFetch(
    "http://example.com/api/v1/daemon/presence/heartbeat",
    {
      method: "POST",
      headers,
      body: options?.rawBody ?? JSON.stringify(payload),
    }
  );
}

export function makePresenceReadToken(
  userId: string,
  deviceId: string,
  overrides: Partial<Record<string, unknown>> = {}
) {
  const now = Date.now();
  return createPresenceToken({
    token_id: "token",
    user_id: userId,
    device_id: deviceId,
    scope: ["presence:read"],
    exp_ms: now + 10_000,
    issued_at_ms: now,
    ...overrides,
  });
}

export async function openStream(
  mf: Miniflare,
  userId: string,
  token: string
): Promise<{
  response: Response;
  reader: ReadableStreamDefaultReader<Uint8Array>;
}> {
  const response = await mf.dispatchFetch(
    `http://example.com/api/v1/mobile/presence/stream?user_id=${userId}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    }
  );

  const reader = response.body?.getReader();
  expect(reader).toBeTruthy();

  return {
    response,
    reader: reader!,
  };
}

export async function readSseEvent(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  timeoutMs = 750
): Promise<Record<string, unknown>> {
  const timeout = new Promise<"timeout">((resolve) => {
    setTimeout(() => resolve("timeout"), timeoutMs);
  });

  const result = await Promise.race([reader.read(), timeout]);
  if (result === "timeout") {
    throw new Error("Timed out waiting for SSE data");
  }

  if (!result.value) {
    throw new Error("Missing SSE data");
  }

  const text = new TextDecoder().decode(result.value);
  const matches = [...text.matchAll(/data:\s*(\{[^\n]+\})/g)];
  if (matches.length === 0) {
    throw new Error(`SSE payload did not include JSON data event: ${text}`);
  }

  return JSON.parse(matches[0][1]) as Record<string, unknown>;
}

export async function readDebugState(
  mf: Miniflare,
  userId = defaultUserId
): Promise<DebugState> {
  const response = await mf.dispatchFetch(
    `http://example.com/debug/presence?user_id=${userId}`
  );

  expect(response.status).toBe(200);
  return (await response.json()) as DebugState;
}

export async function waitUntil<T>(
  fn: () => Promise<T>,
  options?: {
    timeoutMs?: number;
    intervalMs?: number;
    predicate?: (value: T) => boolean;
    description?: string;
  }
): Promise<T> {
  const timeoutMs = options?.timeoutMs ?? 1500;
  const intervalMs = options?.intervalMs ?? 20;
  const predicate = options?.predicate ?? (() => true);

  const start = Date.now();
  let lastValue: T | undefined;

  while (Date.now() - start <= timeoutMs) {
    lastValue = await fn();
    if (predicate(lastValue)) {
      return lastValue;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  throw new Error(
    options?.description ??
      `waitUntil timed out after ${timeoutMs}ms (last value: ${JSON.stringify(lastValue)})`
  );
}
