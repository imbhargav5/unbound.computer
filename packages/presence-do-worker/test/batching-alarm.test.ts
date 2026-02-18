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
  readDebugState,
  readSseEvent,
  waitUntil,
} from "./helpers";

describe("presence-do-worker keep-alive batching and alarm behavior", () => {
  let mf: Miniflare;

  beforeEach(() => {
    mf = createMiniflare({ keepAliveFlushMs: 120 });
  });

  afterEach(async () => {
    await disposeMiniflare(mf);
  });

  it("batches repeated keep-alive heartbeats and flushes once", async () => {
    const baseSentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt, ttl_ms: 5000 })
        )
      ).status
    ).toBe(204);

    for (let seq = 2; seq <= 5; seq += 1) {
      expect(
        (
          await dispatchHeartbeat(
            mf,
            makeHeartbeat({ seq, sent_at_ms: baseSentAt + seq, ttl_ms: 5000 })
          )
        ).status
      ).toBe(204);
    }

    const preFlush = await readDebugState(mf);
    expect(preFlush.stats.storage_puts_total).toBe(1);
    expect(preFlush.dirty_devices).toContain(defaultDeviceId);

    const postFlush = await waitUntil(() => readDebugState(mf), {
      predicate: (state) =>
        state.stats.storage_puts_total >= 2 && state.dirty_devices.length === 0,
      timeoutMs: 2000,
      description: "Expected keep-alive batch flush to persist once",
    });

    expect(postFlush.stats.storage_puts_total).toBe(2);
  });

  it("does not slide keep-alive flush deadline while a device is already dirty", async () => {
    const baseSentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt, ttl_ms: 3000 })
        )
      ).status
    ).toBe(204);

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 2, sent_at_ms: baseSentAt + 2, ttl_ms: 3000 })
        )
      ).status
    ).toBe(204);

    const firstDirty = await readDebugState(mf);
    expect(firstDirty.next_flush_ms).not.toBeNull();

    await new Promise((resolve) => setTimeout(resolve, 40));

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 3, sent_at_ms: baseSentAt + 3, ttl_ms: 3000 })
        )
      ).status
    ).toBe(204);

    const secondDirty = await readDebugState(mf);
    expect(secondDirty.next_flush_ms).toBe(firstDirty.next_flush_ms);
  });

  it("writes immediately for transitions and semantic changes", async () => {
    const baseSentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt, ttl_ms: 12_000 })
        )
      ).status
    ).toBe(204);
    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 2, sent_at_ms: baseSentAt + 2, ttl_ms: 12_000 })
        )
      ).status
    ).toBe(204);

    const afterKeepAlive = await readDebugState(mf);
    expect(afterKeepAlive.stats.storage_puts_total).toBe(1);
    expect(afterKeepAlive.dirty_devices).toContain(defaultDeviceId);

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            status: "offline",
            seq: 3,
            sent_at_ms: baseSentAt + 3,
          })
        )
      ).status
    ).toBe(204);

    const afterOffline = await readDebugState(mf);
    expect(afterOffline.stats.storage_puts_total).toBe(2);
    expect(afterOffline.dirty_devices).toEqual([]);

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            status: "online",
            seq: 4,
            sent_at_ms: baseSentAt + 4,
          })
        )
      ).status
    ).toBe(204);
    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 5, sent_at_ms: baseSentAt + 5, ttl_ms: 15_000 })
        )
      ).status
    ).toBe(204);
    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            seq: 6,
            sent_at_ms: baseSentAt + 6,
            ttl_ms: 15_000,
            source: "daemon-alt",
          })
        )
      ).status
    ).toBe(204);

    const finalState = await readDebugState(mf);
    expect(finalState.stats.storage_puts_total).toBe(5);

    const persistedRecord = finalState.records[`device:${defaultDeviceId}`];
    expect(persistedRecord.status).toBe("online");
    expect(persistedRecord.source).toBe("daemon-alt");
    expect(persistedRecord.ttl_ms).toBe(15_000);
  });

  it("schedules alarm based on earliest flush/expiry target", async () => {
    const baseSentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt, ttl_ms: 5000 })
        )
      ).status
    ).toBe(204);
    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 2, sent_at_ms: baseSentAt + 2, ttl_ms: 5000 })
        )
      ).status
    ).toBe(204);

    const withFlush = await readDebugState(mf);
    expect(withFlush.next_flush_ms).not.toBeNull();
    expect(withFlush.next_expiry_ms).not.toBeNull();
    expect(withFlush.next_alarm_ms).toBe(
      Math.min(withFlush.next_flush_ms!, withFlush.next_expiry_ms!)
    );

    const secondDevice = "123e4567-e89b-12d3-a456-426614174055";
    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            device_id: secondDevice,
            seq: 1,
            sent_at_ms: baseSentAt + 3,
            ttl_ms: 40,
          })
        )
      ).status
    ).toBe(204);

    const withEarlyExpiry = await readDebugState(mf);
    expect(withEarlyExpiry.next_alarm_ms).toBe(
      Math.min(
        withEarlyExpiry.next_flush_ms ?? Number.POSITIVE_INFINITY,
        withEarlyExpiry.next_expiry_ms ?? Number.POSITIVE_INFINITY
      )
    );
  });

  it("clears alarm when no online devices and no dirty keep-alives remain", async () => {
    const baseSentAt = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ status: "online", seq: 1, sent_at_ms: baseSentAt })
        )
      ).status
    ).toBe(204);

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            status: "offline",
            seq: 2,
            sent_at_ms: baseSentAt + 1,
          })
        )
      ).status
    ).toBe(204);

    const state = await readDebugState(mf);
    expect(state.next_alarm_ms).toBeNull();
    expect(state.alarm).toBeNull();
    expect(state.stats.delete_alarm_total).toBeGreaterThanOrEqual(1);
  });

  it("emits offline event after ttl expiry and persists last_offline_ms", async () => {
    const token = makePresenceReadToken(defaultUserId, defaultDeviceId);
    const stream = await openStream(mf, defaultUserId, token);

    const baseSentAt = Date.now();
    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt, ttl_ms: 45 })
        )
      ).status
    ).toBe(204);

    const online = await readSseEvent(stream.reader, 1000);
    expect(online.status).toBe("online");

    const offline = await readSseEvent(stream.reader, 2000);
    expect(offline.status).toBe("offline");

    const state = await readDebugState(mf);
    const persistedRecord = state.records[`device:${defaultDeviceId}`];
    expect(persistedRecord.status).toBe("offline");
    expect(persistedRecord.last_offline_ms).not.toBeNull();

    await stream.reader.cancel();
  });

  it("avoids alarm churn when keep-alive comes from non-earliest device", async () => {
    const firstDevice = defaultDeviceId;
    const secondDevice = "123e4567-e89b-12d3-a456-426614174066";
    const now = Date.now();

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            device_id: firstDevice,
            seq: 1,
            sent_at_ms: now,
            ttl_ms: 80,
          })
        )
      ).status
    ).toBe(204);

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            device_id: secondDevice,
            seq: 1,
            sent_at_ms: now + 1,
            ttl_ms: 1000,
          })
        )
      ).status
    ).toBe(204);

    expect(
      (
        await dispatchHeartbeat(
          mf,
          makeHeartbeat({
            device_id: secondDevice,
            seq: 2,
            sent_at_ms: now + 2,
            ttl_ms: 1000,
          })
        )
      ).status
    ).toBe(204);

    const state = await readDebugState(mf);
    expect(state.stats.set_alarm_total).toBe(1);
  });
});
