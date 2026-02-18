import type { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  createMiniflare,
  defaultDeviceId,
  defaultUserId,
  dispatchHeartbeat,
  disposeMiniflare,
  ingestToken,
  makeHeartbeat,
} from "./helpers";

describe("presence-do-worker auth and payload validation", () => {
  let mf: Miniflare;

  beforeEach(() => {
    mf = createMiniflare({ keepAliveFlushMs: 120 });
  });

  afterEach(async () => {
    await disposeMiniflare(mf);
  });

  it("rejects heartbeat without auth", async () => {
    const response = await dispatchHeartbeat(mf, makeHeartbeat(), {
      token: "",
    });

    expect(response.status).toBe(401);
    const body = await response.json();
    expect(body.error).toBe("unauthorized");
  });

  it("rejects heartbeat with invalid auth token", async () => {
    const response = await dispatchHeartbeat(mf, makeHeartbeat(), {
      token: "wrong-token",
    });

    expect(response.status).toBe(401);
  });

  it("rejects invalid json body", async () => {
    const response = await mf.dispatchFetch(
      "http://example.com/api/v1/daemon/presence/heartbeat",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${ingestToken}`,
        },
        body: "{not-json",
      }
    );

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error).toBe("invalid_payload");
  });

  it("rejects invalid schema version", async () => {
    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ schema_version: 2 })
    );

    expect(response.status).toBe(400);
  });

  it("rejects uppercase identifiers", async () => {
    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({
        user_id: defaultUserId.toUpperCase(),
        device_id: defaultDeviceId.toUpperCase(),
      })
    );

    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.details).toContain("lowercase");
  });

  it("rejects invalid status", async () => {
    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ status: "online" as never, source: "daemon-do" }),
      {
        rawBody: JSON.stringify({
          ...makeHeartbeat(),
          status: "unknown",
        }),
      }
    );

    expect(response.status).toBe(400);
  });

  it("rejects empty source", async () => {
    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ source: "   " })
    );

    expect(response.status).toBe(400);
  });

  it("rejects negative sent_at_ms", async () => {
    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ sent_at_ms: -1 })
    );

    expect(response.status).toBe(400);
  });

  it("rejects negative seq", async () => {
    const response = await dispatchHeartbeat(mf, makeHeartbeat({ seq: -1 }));

    expect(response.status).toBe(400);
  });

  it("rejects non-positive ttl_ms", async () => {
    const response = await dispatchHeartbeat(mf, makeHeartbeat({ ttl_ms: 0 }));

    expect(response.status).toBe(400);
  });

  it("rejects non-monotonic heartbeat when both seq and sent_at_ms do not advance", async () => {
    const sentAt = Date.now();

    const first = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ seq: 1, sent_at_ms: sentAt })
    );
    expect(first.status).toBe(204);

    const stale = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ seq: 1, sent_at_ms: sentAt })
    );

    expect(stale.status).toBe(409);
  });

  it("accepts heartbeat with higher seq when sent_at_ms stays the same", async () => {
    const sentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: sentAt })
        )
      ).status
    ).toBe(204);

    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ seq: 2, sent_at_ms: sentAt })
    );

    expect(response.status).toBe(204);
  });

  it("accepts heartbeat with higher sent_at_ms when seq stays the same", async () => {
    const sentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 7, sent_at_ms: sentAt })
        )
      ).status
    ).toBe(204);

    const response = await dispatchHeartbeat(
      mf,
      makeHeartbeat({ seq: 7, sent_at_ms: sentAt + 1 })
    );

    expect(response.status).toBe(204);
  });
});
