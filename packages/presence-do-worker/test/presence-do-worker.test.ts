import { createHmac } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

const signingKey = "presence-signing-test";
const ingestToken = "presence-ingest-test";

function base64UrlEncode(input: string | Buffer) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=+$/, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function createPresenceToken(payload: Record<string, unknown>) {
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signature = base64UrlEncode(
    createHmac("sha256", signingKey).update(encodedPayload).digest()
  );
  return `${encodedPayload}.${signature}`;
}

async function readSseChunk(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  timeoutMs = 250
) {
  const timeout = new Promise<"timeout">((resolve) =>
    setTimeout(() => resolve("timeout"), timeoutMs)
  );
  const result = await Promise.race([reader.read(), timeout]);
  if (result === "timeout") {
    throw new Error("Timed out waiting for SSE data");
  }
  if (!result.value) {
    throw new Error("Missing SSE data");
  }
  return new TextDecoder().decode(result.value);
}

describe("presence DO worker", () => {
  let mf: Miniflare;

  beforeEach(() => {
    const __dirname = path.dirname(fileURLToPath(import.meta.url));
    mf = new Miniflare({
      scriptPath: path.resolve(__dirname, "../src/index.ts"),
      modules: true,
      compatibilityDate: "2025-02-01",
      durableObjects: { PRESENCE_DO: "PresenceDurableObject" },
      bindings: {
        PRESENCE_DO_TOKEN_SIGNING_KEY: signingKey,
        PRESENCE_DO_INGEST_TOKEN: ingestToken,
      },
    });
  });

  afterEach(async () => {
    await mf.dispose();
  });

  it("rejects heartbeat without auth", async () => {
    const response = await mf.dispatchFetch(
      "http://example.com/api/v1/daemon/presence/heartbeat",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      }
    );

    expect(response.status).toBe(401);
    const body = await response.json();
    expect(body.error).toBe("unauthorized");
  });

  it("streams last-known presence state", async () => {
    const userId = "123e4567-e89b-12d3-a456-426614174000";
    const deviceId = "123e4567-e89b-12d3-a456-426614174001";
    const now = Date.now();

    const heartbeat = {
      schema_version: 1,
      user_id: userId,
      device_id: deviceId,
      status: "online",
      source: "daemon-do",
      sent_at_ms: now,
      seq: 1,
      ttl_ms: 10_000,
    };

    const heartbeatResponse = await mf.dispatchFetch(
      "http://example.com/api/v1/daemon/presence/heartbeat",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${ingestToken}`,
        },
        body: JSON.stringify(heartbeat),
      }
    );
    expect(heartbeatResponse.status).toBe(204);

    const token = createPresenceToken({
      token_id: "token",
      user_id: userId,
      device_id: deviceId,
      scope: ["presence:read"],
      exp_ms: now + 10_000,
      issued_at_ms: now,
    });

    const streamResponse = await mf.dispatchFetch(
      `http://example.com/api/v1/mobile/presence/stream?user_id=${userId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      }
    );

    expect(streamResponse.status).toBe(200);
    const reader = streamResponse.body?.getReader();
    expect(reader).toBeTruthy();

    const chunk = await readSseChunk(reader!);
    const match = chunk.match(/data:\s*(\{.*\})/);
    expect(match).not.toBeNull();
    const payload = JSON.parse(match![1]);
    expect(payload.user_id).toBe(userId);
    expect(payload.device_id).toBe(deviceId);
    expect(payload.status).toBe("online");
  });

  it("emits offline event after TTL expiry", async () => {
    const userId = "123e4567-e89b-12d3-a456-426614174002";
    const deviceId = "123e4567-e89b-12d3-a456-426614174003";
    const now = Date.now();

    const token = createPresenceToken({
      token_id: "token",
      user_id: userId,
      device_id: deviceId,
      scope: ["presence:read"],
      exp_ms: now + 10_000,
      issued_at_ms: now,
    });

    const streamResponse = await mf.dispatchFetch(
      `http://example.com/api/v1/mobile/presence/stream?user_id=${userId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      }
    );

    const reader = streamResponse.body?.getReader();
    expect(reader).toBeTruthy();

    const heartbeat = {
      schema_version: 1,
      user_id: userId,
      device_id: deviceId,
      status: "online",
      source: "daemon-do",
      sent_at_ms: now,
      seq: 1,
      ttl_ms: 25,
    };

    await mf.dispatchFetch(
      "http://example.com/api/v1/daemon/presence/heartbeat",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${ingestToken}`,
        },
        body: JSON.stringify(heartbeat),
      }
    );

    await readSseChunk(reader!);
    await new Promise((resolve) => setTimeout(resolve, 50));

    const offlineChunk = await readSseChunk(reader!);
    const match = offlineChunk.match(/data:\s*(\{.*\})/);
    expect(match).not.toBeNull();
    const payload = JSON.parse(match![1]);
    expect(payload.status).toBe("offline");
  });
});
