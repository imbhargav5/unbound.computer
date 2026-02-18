import type { Miniflare } from "miniflare";
import { afterEach, describe, expect, it } from "vitest";
import {
  createMiniflare,
  createPersistPath,
  defaultDeviceId,
  defaultUserId,
  dispatchHeartbeat,
  disposeMiniflare,
  makeHeartbeat,
  makePresenceReadToken,
  openStream,
  readDebugState,
  readSseEvent,
} from "./helpers";

describe("presence-do-worker cold start behavior", () => {
  const instances: Miniflare[] = [];

  afterEach(async () => {
    for (const mf of instances.splice(0, instances.length)) {
      await disposeMiniflare(mf);
    }
  });

  it("rehydrates from persisted storage and drops unsynced keep-alive state across restart", async () => {
    const persistPath = await createPersistPath();
    const baseSentAt = Date.now();

    const mf1 = createMiniflare({
      keepAliveFlushMs: 5000,
      durableObjectsPersist: persistPath,
    });
    instances.push(mf1);

    expect(
      (
        await dispatchHeartbeat(
          mf1,
          makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt, ttl_ms: 20_000 })
        )
      ).status
    ).toBe(204);

    expect(
      (
        await dispatchHeartbeat(
          mf1,
          makeHeartbeat({ seq: 2, sent_at_ms: baseSentAt + 2, ttl_ms: 20_000 })
        )
      ).status
    ).toBe(204);

    const beforeRestart = await readDebugState(mf1);
    expect(beforeRestart.records[`device:${defaultDeviceId}`].seq).toBe(1);
    expect(beforeRestart.dirty_devices).toContain(defaultDeviceId);

    await disposeMiniflare(mf1);
    instances.splice(instances.indexOf(mf1), 1);

    const mf2 = createMiniflare({
      keepAliveFlushMs: 5000,
      durableObjectsPersist: persistPath,
    });
    instances.push(mf2);

    const afterRestart = await readDebugState(mf2);
    expect(afterRestart.records[`device:${defaultDeviceId}`].seq).toBe(1);
    expect(afterRestart.dirty_devices).toEqual([]);

    const token = makePresenceReadToken(defaultUserId, defaultDeviceId);
    const stream = await openStream(mf2, defaultUserId, token);
    const bootstrap = await readSseEvent(stream.reader, 1500);
    expect(bootstrap.seq).toBe(1);
    await stream.reader.cancel();

    const replayedKeepAlive = await dispatchHeartbeat(
      mf2,
      makeHeartbeat({ seq: 2, sent_at_ms: baseSentAt + 2, ttl_ms: 20_000 })
    );
    expect(replayedKeepAlive.status).toBe(204);

    const stale = await dispatchHeartbeat(
      mf2,
      makeHeartbeat({ seq: 1, sent_at_ms: baseSentAt + 1, ttl_ms: 20_000 })
    );
    expect(stale.status).toBe(409);
  });
});
