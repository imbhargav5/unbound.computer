import type { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  createMiniflare,
  defaultDeviceId,
  defaultUserId,
  dispatchHeartbeat,
  disposeMiniflare,
  makeHeartbeat,
  makePresenceReadToken,
  openStream,
  readSseEvent,
} from "./helpers";

describe("presence-do-worker stream behavior", () => {
  let mf: Miniflare;

  beforeEach(() => {
    mf = createMiniflare({ keepAliveFlushMs: 5000 });
  });

  afterEach(async () => {
    await disposeMiniflare(mf);
  });

  it("streams last-known presence snapshot", async () => {
    const now = Date.now();
    const heartbeat = makeHeartbeat({
      sent_at_ms: now,
      seq: 1,
      ttl_ms: 10_000,
    });
    expect((await dispatchHeartbeat(mf, heartbeat)).status).toBe(204);

    const token = makePresenceReadToken(defaultUserId, defaultDeviceId);
    const { response, reader } = await openStream(mf, defaultUserId, token);

    expect(response.status).toBe(200);

    const payload = await readSseEvent(reader);
    expect(payload.user_id).toBe(defaultUserId);
    expect(payload.device_id).toBe(defaultDeviceId);
    expect(payload.status).toBe("online");
    expect(payload.seq).toBe(1);

    await reader.cancel();
  });

  it("returns in-memory latest heartbeat in stream bootstrap before keep-alive flush", async () => {
    const now = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: now, ttl_ms: 12_000 })
        )
      ).status
    ).toBe(204);

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 2, sent_at_ms: now + 5, ttl_ms: 12_000 })
        )
      ).status
    ).toBe(204);

    const token = makePresenceReadToken(defaultUserId, defaultDeviceId);
    const { reader } = await openStream(mf, defaultUserId, token);

    const payload = await readSseEvent(reader);
    expect(payload.seq).toBe(2);
    expect(payload.sent_at_ms).toBe(now + 5);

    await reader.cancel();
  });

  it("broadcasts updates to multiple connected stream clients", async () => {
    const token1 = makePresenceReadToken(defaultUserId, defaultDeviceId);
    const token2 = makePresenceReadToken(
      defaultUserId,
      "123e4567-e89b-12d3-a456-426614174099"
    );

    const stream1 = await openStream(mf, defaultUserId, token1);
    const stream2 = await openStream(mf, defaultUserId, token2);

    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ seq: 1, sent_at_ms: Date.now() })
    );
    expect(response.status).toBe(204);

    const [event1, event2] = await Promise.all([
      readSseEvent(stream1.reader),
      readSseEvent(stream2.reader),
    ]);

    expect(event1.device_id).toBe(defaultDeviceId);
    expect(event2.device_id).toBe(defaultDeviceId);

    await stream1.reader.cancel();
    await stream2.reader.cancel();
  });

  it("requires bearer token for stream", async () => {
    const response = await mf.dispatchFetch(
      `http://example.com/api/v1/mobile/presence/stream?user_id=${defaultUserId}`
    );

    expect(response.status).toBe(401);
  });

  it("rejects invalid stream token", async () => {
    const response = await mf.dispatchFetch(
      `http://example.com/api/v1/mobile/presence/stream?user_id=${defaultUserId}`,
      {
        headers: {
          Authorization: "Bearer not-a-valid-token",
        },
      }
    );

    expect(response.status).toBe(403);
  });

  it("rejects expired stream token", async () => {
    const token = makePresenceReadToken(defaultUserId, defaultDeviceId, {
      exp_ms: Date.now() - 10,
    });

    const response = await mf.dispatchFetch(
      `http://example.com/api/v1/mobile/presence/stream?user_id=${defaultUserId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      }
    );

    expect(response.status).toBe(403);
    const body = await response.json();
    expect(body.details).toContain("expired");
  });

  it("rejects stream token without presence:read scope", async () => {
    const token = makePresenceReadToken(defaultUserId, defaultDeviceId, {
      scope: ["something:else"],
    });

    const response = await mf.dispatchFetch(
      `http://example.com/api/v1/mobile/presence/stream?user_id=${defaultUserId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      }
    );

    expect(response.status).toBe(403);
  });

  it("rejects stream token user mismatch", async () => {
    const token = makePresenceReadToken(defaultUserId, defaultDeviceId);

    const response = await mf.dispatchFetch(
      "http://example.com/api/v1/mobile/presence/stream?user_id=123e4567-e89b-12d3-a456-426614174088",
      {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      }
    );

    expect(response.status).toBe(403);
  });
});
