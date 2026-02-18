import type { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  createMiniflare,
  defaultDeviceId,
  defaultUserId,
  dispatchHeartbeat,
  disposeMiniflare,
  makeHeartbeat,
  readDebugState,
} from "./helpers";

describe("presence-do-worker debug endpoint", () => {
  let mf: Miniflare;

  beforeEach(() => {
    mf = createMiniflare({ keepAliveFlushMs: 150 });
  });

  afterEach(async () => {
    await disposeMiniflare(mf);
  });

  it("returns expanded debug fields and stats", async () => {
    const baseSentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt, ttl_ms: 4000 })
        )
      ).status
    ).toBe(204);
    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 2, sent_at_ms: baseSentAt + 2, ttl_ms: 4000 })
        )
      ).status
    ).toBe(204);

    const state = await readDebugState(mf);

    expect(state.cache_loaded).toBe(true);
    expect(state.dirty_devices).toContain(defaultDeviceId);
    expect(state.next_flush_ms).toBeTypeOf("number");
    expect(state.next_expiry_ms).toBeTypeOf("number");
    expect(state.next_alarm_ms).toBeTypeOf("number");

    expect(state.stats.storage_puts_total).toBeGreaterThanOrEqual(1);
    expect(state.stats.set_alarm_total).toBeGreaterThanOrEqual(1);
    expect(state.stats.list_records_total).toBeGreaterThanOrEqual(1);

    expect(state.records[`device:${defaultDeviceId}`]).toBeDefined();
    expect(state.records[`device:${defaultDeviceId}`].seq).toBe(1);
  });

  it("increments list_records_total on subsequent debug reads", async () => {
    expect((await dispatchHeartbeat(mf, makeHeartbeat())).status).toBe(204);

    const first = await readDebugState(mf);
    const second = await readDebugState(mf);

    expect(second.stats.list_records_total).toBeGreaterThan(
      first.stats.list_records_total
    );
  });

  it("disables debug endpoint in production", async () => {
    await disposeMiniflare(mf);
    mf = createMiniflare({ environment: "production" });

    const response = await mf.dispatchFetch(
      `http://example.com/debug/presence?user_id=${defaultUserId}`
    );

    expect(response.status).toBe(403);
    const body = await response.json();
    expect(body.details).toContain("disabled");
  });
});
