const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const uuidRegex =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const DEFAULT_KEEPALIVE_FLUSH_MS = 30_000;

interface PresencePayload {
  schema_version: number;
  user_id: string;
  device_id: string;
  status: "online" | "offline";
  source: string;
  sent_at_ms: number;
  seq: number;
  ttl_ms: number;
}

interface PresenceStorageRecord extends PresencePayload {
  last_heartbeat_ms: number;
  last_offline_ms: number | null;
  updated_at_ms: number;
}

interface PresenceTokenPayload {
  token_id: string;
  user_id: string;
  device_id: string;
  scope: string[];
  exp_ms: number;
  issued_at_ms: number;
}

interface PresenceDebugStats {
  storage_puts_total: number;
  set_alarm_total: number;
  delete_alarm_total: number;
  list_records_total: number;
}

interface Env {
  PRESENCE_DO: DurableObjectNamespace;
  PRESENCE_DO_TOKEN_SIGNING_KEY: string;
  PRESENCE_DO_INGEST_TOKEN: string;
  ENVIRONMENT: string;
  PRESENCE_DO_KEEPALIVE_FLUSH_MS?: string;
}

function jsonResponse(
  body: unknown,
  status: number,
  extraHeaders?: HeadersInit
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
      ...(extraHeaders ?? {}),
    },
  });
}

function normalizeIdentifier(value: string | undefined | null) {
  return (value ?? "").trim().toLowerCase();
}

function isUuid(value: string) {
  return uuidRegex.test(value);
}

function parseKeepAliveFlushMs(value: string | undefined) {
  const parsed = Number.parseInt((value ?? "").trim(), 10);
  if (Number.isFinite(parsed) && parsed > 0) {
    return parsed;
  }
  return DEFAULT_KEEPALIVE_FLUSH_MS;
}

function base64UrlToBytes(input: string): Uint8Array {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/");
  const padLength = (4 - (padded.length % 4)) % 4;
  const paddedValue = padded + "=".repeat(padLength);
  const binary = atob(paddedValue);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function verifyPresenceToken(
  token: string,
  signingKey: string
): Promise<PresenceTokenPayload | null> {
  const [payloadPart, signaturePart] = token.split(".");
  if (!(payloadPart && signaturePart)) return null;
  if (!signingKey) return null;

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(signingKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const signatureBytes = base64UrlToBytes(signaturePart);
  const ok = await crypto.subtle.verify(
    "HMAC",
    key,
    signatureBytes as unknown as BufferSource,
    encoder.encode(payloadPart)
  );
  if (!ok) return null;

  const payloadBytes = base64UrlToBytes(payloadPart);
  const payloadJson = decoder.decode(payloadBytes);
  const payload = JSON.parse(payloadJson) as PresenceTokenPayload;
  if (!payload || typeof payload !== "object") return null;
  return payload;
}

function buildPresenceError(error: string, details?: string) {
  return { error, details };
}

function parseBearerToken(header: string | null) {
  if (!header) return "";
  const [type, value] = header.split(" ");
  if (!type || type.toLowerCase() !== "bearer") return "";
  return value ?? "";
}

function logEvent(event: string, data?: Record<string, unknown>) {
  const payload = data ? { event, ...data } : { event };
  console.log(JSON.stringify(payload));
}

interface PresencePayloadValidationSuccess {
  ok: true;
  payload: PresencePayload;
}

interface PresencePayloadValidationFailure {
  ok: false;
  error: "invalid_payload";
  details: string;
}

function validatePresencePayload(
  input: unknown
): PresencePayloadValidationSuccess | PresencePayloadValidationFailure {
  if (!input || typeof input !== "object") {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid JSON payload",
    };
  }
  const payload = input as Partial<PresencePayload>;
  if (payload.schema_version !== 1) {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid schema_version",
    };
  }
  const userId = normalizeIdentifier(payload.user_id ?? "");
  const deviceId = normalizeIdentifier(payload.device_id ?? "");
  if (!(userId && deviceId && isUuid(userId) && isUuid(deviceId))) {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid user_id or device_id",
    };
  }
  if (payload.user_id !== userId || payload.device_id !== deviceId) {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Identifiers must be lowercase",
    };
  }
  if (payload.status !== "online" && payload.status !== "offline") {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid status",
    };
  }
  if (
    typeof payload.source !== "string" ||
    payload.source.trim().length === 0
  ) {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid source",
    };
  }
  if (!Number.isFinite(payload.sent_at_ms) || (payload.sent_at_ms ?? 0) < 0) {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid sent_at_ms",
    };
  }
  if (!Number.isFinite(payload.seq) || (payload.seq ?? -1) < 0) {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid seq",
    };
  }
  if (!Number.isFinite(payload.ttl_ms) || (payload.ttl_ms ?? 0) <= 0) {
    return {
      ok: false,
      error: "invalid_payload" as const,
      details: "Invalid ttl_ms",
    };
  }

  return {
    ok: true,
    payload: {
      schema_version: payload.schema_version,
      user_id: userId,
      device_id: deviceId,
      status: payload.status,
      source: payload.source.trim(),
      sent_at_ms: payload.sent_at_ms,
      seq: payload.seq,
      ttl_ms: payload.ttl_ms,
    } as PresencePayload,
  };
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (url.pathname === "/debug/presence" && request.method === "GET") {
      if (env.ENVIRONMENT === "production") {
        return jsonResponse(
          buildPresenceError(
            "unavailable",
            "Debug endpoint disabled in production"
          ),
          403
        );
      }
      const userId = normalizeIdentifier(url.searchParams.get("user_id"));
      if (!userId) {
        return jsonResponse(
          buildPresenceError("invalid_payload", "Missing user_id query param"),
          400
        );
      }
      const id = env.PRESENCE_DO.idFromName(userId);
      const stub = env.PRESENCE_DO.get(id);
      return stub.fetch(request);
    }

    if (
      url.pathname === "/api/v1/daemon/presence/heartbeat" ||
      url.pathname === "/api/v1/mobile/presence/stream"
    ) {
      let userId = "";

      if (url.pathname === "/api/v1/mobile/presence/stream") {
        userId = normalizeIdentifier(url.searchParams.get("user_id"));
        if (!userId) {
          return jsonResponse(
            buildPresenceError("invalid_payload", "Missing user_id"),
            400
          );
        }
      } else {
        try {
          const body = await request.clone().json();
          if (body && typeof body === "object" && "user_id" in body) {
            userId = normalizeIdentifier(
              (body as { user_id?: string }).user_id
            );
          }
        } catch {
          return jsonResponse(
            buildPresenceError("invalid_payload", "Invalid JSON payload"),
            400
          );
        }
      }

      if (!userId) {
        return jsonResponse(
          buildPresenceError("invalid_payload", "Missing user_id"),
          400
        );
      }

      const id = env.PRESENCE_DO.idFromName(userId);
      const stub = env.PRESENCE_DO.get(id);
      return stub.fetch(request);
    }

    return jsonResponse(
      buildPresenceError("unavailable", "Route not found"),
      404
    );
  },
} satisfies ExportedHandler<Env>;

export class PresenceDurableObject {
  private state: DurableObjectState;
  private env: Env;
  private keepAliveFlushMs: number;
  private streams = new Map<
    string,
    ReadableStreamDefaultController<Uint8Array>
  >();

  private recordsByDevice = new Map<string, PresenceStorageRecord>();
  private dirtyKeepAlive = new Set<string>();
  private flushDeadlineByDevice = new Map<string, number>();
  private cacheLoaded = false;
  private currentAlarmMs: number | null = null;

  private stats: PresenceDebugStats = {
    storage_puts_total: 0,
    set_alarm_total: 0,
    delete_alarm_total: 0,
    list_records_total: 0,
  };

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
    this.keepAliveFlushMs = parseKeepAliveFlushMs(
      env.PRESENCE_DO_KEEPALIVE_FLUSH_MS
    );
  }

  async fetch(request: Request) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (url.pathname === "/debug/presence") {
      return this.handleDebug();
    }

    if (url.pathname === "/api/v1/daemon/presence/heartbeat") {
      return this.handleHeartbeat(request);
    }

    if (url.pathname === "/api/v1/mobile/presence/stream") {
      return this.handleStream(request, url);
    }

    return jsonResponse(
      buildPresenceError("unavailable", "Route not found"),
      404
    );
  }

  async alarm() {
    await this.ensureCacheLoaded();
    // The scheduled alarm has just fired; clear in-memory marker before recalculation.
    this.currentAlarmMs = null;
    const now = Date.now();

    await this.flushDueKeepAlive(now);

    for (const [deviceId, record] of this.recordsByDevice.entries()) {
      if (
        record.status === "online" &&
        now - record.last_heartbeat_ms >= record.ttl_ms
      ) {
        const updated: PresenceStorageRecord = {
          ...record,
          status: "offline",
          last_offline_ms: now,
          updated_at_ms: now,
        };
        this.recordsByDevice.set(deviceId, updated);
        this.clearDirty(deviceId);
        await this.persistRecord(updated);
        this.broadcast(this.toStreamPayload(updated, now));
      }
    }

    await this.reconcileAlarm();
  }

  private async handleHeartbeat(request: Request) {
    const ingestToken = this.env.PRESENCE_DO_INGEST_TOKEN?.trim();
    if (!ingestToken) {
      logEvent("presence.do.heartbeat.unavailable");
      return jsonResponse(
        buildPresenceError(
          "unavailable",
          "Presence DO ingest token is not configured"
        ),
        503
      );
    }

    const authHeader = parseBearerToken(request.headers.get("Authorization"));
    if (!authHeader || authHeader !== ingestToken) {
      logEvent("presence.do.heartbeat.unauthorized");
      return jsonResponse(
        buildPresenceError("unauthorized", "Unauthorized"),
        401
      );
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return jsonResponse(
        buildPresenceError("invalid_payload", "Invalid JSON payload"),
        400
      );
    }

    const validation = validatePresencePayload(body);
    if (!validation.ok) {
      logEvent("presence.do.heartbeat.invalid_payload", {
        reason: validation.details,
      });
      return jsonResponse(
        buildPresenceError(validation.error, validation.details),
        400
      );
    }

    await this.ensureCacheLoaded();

    const payload = validation.payload;
    const existing = this.recordsByDevice.get(payload.device_id);
    if (
      existing &&
      payload.seq <= existing.seq &&
      payload.sent_at_ms <= existing.sent_at_ms
    ) {
      logEvent("presence.do.heartbeat.non_monotonic", {
        device_id: payload.device_id,
      });
      return jsonResponse(
        buildPresenceError("invalid_payload", "Non-monotonic seq"),
        409
      );
    }

    const now = Date.now();
    const lastHeartbeat =
      payload.status === "online"
        ? payload.sent_at_ms
        : (existing?.last_heartbeat_ms ?? payload.sent_at_ms);

    const record: PresenceStorageRecord = {
      ...payload,
      last_heartbeat_ms: lastHeartbeat,
      last_offline_ms: payload.status === "offline" ? payload.sent_at_ms : null,
      updated_at_ms: now,
    };

    this.recordsByDevice.set(payload.device_id, record);

    if (this.isKeepAlive(existing, payload)) {
      this.markKeepAliveDirty(payload.device_id, now);
    } else {
      this.clearDirty(payload.device_id);
      await this.persistRecord(record);
    }

    this.broadcast(this.toStreamPayload(record, payload.sent_at_ms));
    await this.reconcileAlarm();

    logEvent("presence.do.heartbeat.accepted", {
      user_id: payload.user_id,
      device_id: payload.device_id,
      status: payload.status,
    });
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  private async handleStream(request: Request, url: URL) {
    const signingKey = this.env.PRESENCE_DO_TOKEN_SIGNING_KEY?.trim();
    if (!signingKey) {
      logEvent("presence.do.stream.unavailable");
      return jsonResponse(
        buildPresenceError(
          "unavailable",
          "Presence DO token signing key is not configured"
        ),
        503
      );
    }

    const token = parseBearerToken(request.headers.get("Authorization"));
    if (!token) {
      logEvent("presence.do.stream.unauthorized");
      return jsonResponse(
        buildPresenceError("unauthorized", "Unauthorized"),
        401
      );
    }

    const payload = await verifyPresenceToken(token, signingKey);
    if (!payload) {
      logEvent("presence.do.stream.invalid_token");
      return jsonResponse(
        buildPresenceError("forbidden", "Invalid token"),
        403
      );
    }

    const now = Date.now();
    if (payload.exp_ms <= now) {
      logEvent("presence.do.stream.token_expired", {
        user_id: payload.user_id,
      });
      return jsonResponse(
        buildPresenceError("forbidden", "Token expired"),
        403
      );
    }

    if (!payload.scope?.includes("presence:read")) {
      logEvent("presence.do.stream.forbidden_scope", {
        user_id: payload.user_id,
      });
      return jsonResponse(
        buildPresenceError("forbidden", "Insufficient scope"),
        403
      );
    }

    const userId = normalizeIdentifier(url.searchParams.get("user_id"));
    if (!userId || payload.user_id !== userId) {
      logEvent("presence.do.stream.user_mismatch", {
        token_user_id: payload.user_id,
        requested_user_id: userId,
      });
      return jsonResponse(
        buildPresenceError("forbidden", "Token user mismatch"),
        403
      );
    }

    const streamId = crypto.randomUUID();
    const stream = new ReadableStream<Uint8Array>({
      start: async (controller) => {
        this.streams.set(streamId, controller);
        request.signal.addEventListener("abort", () => {
          this.streams.delete(streamId);
          logEvent("presence.do.stream.disconnect", {
            user_id: payload.user_id,
          });
        });

        await this.ensureCacheLoaded();
        for (const record of this.recordsByDevice.values()) {
          controller.enqueue(
            encoder.encode(
              `data: ${JSON.stringify(this.toStreamPayload(record))}\n\n`
            )
          );
        }

        logEvent("presence.do.stream.connect", {
          user_id: payload.user_id,
          device_id: payload.device_id,
        });
      },
      cancel: () => {
        this.streams.delete(streamId);
        logEvent("presence.do.stream.disconnect", { user_id: payload.user_id });
      },
    });

    return new Response(stream, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  }

  private async handleDebug() {
    await this.ensureCacheLoaded();

    const records = await this.listPersistedDeviceRecords();
    const entries: Record<string, PresenceStorageRecord> = {};
    for (const [key, value] of records.entries()) {
      entries[key] = value;
    }

    const alarm = await this.state.storage.getAlarm();
    this.currentAlarmMs = alarm ?? null;

    return jsonResponse(
      {
        active_streams: this.streams.size,
        alarm: alarm ? new Date(alarm).toISOString() : null,
        records: entries,
        cache_loaded: this.cacheLoaded,
        dirty_devices: [...this.dirtyKeepAlive.values()].sort(),
        next_flush_ms: this.computeNextFlushMs(),
        next_expiry_ms: this.computeNextExpiryMs(),
        next_alarm_ms: this.computeNextAlarmMs(),
        stats: this.stats,
      },
      200
    );
  }

  private isKeepAlive(
    existing: PresenceStorageRecord | undefined,
    payload: PresencePayload
  ) {
    return Boolean(
      existing &&
        existing.status === "online" &&
        payload.status === "online" &&
        payload.ttl_ms === existing.ttl_ms &&
        payload.source === existing.source
    );
  }

  private markKeepAliveDirty(deviceId: string, now: number) {
    this.dirtyKeepAlive.add(deviceId);
    if (!this.flushDeadlineByDevice.has(deviceId)) {
      this.flushDeadlineByDevice.set(deviceId, now + this.keepAliveFlushMs);
    }
  }

  private clearDirty(deviceId: string) {
    this.dirtyKeepAlive.delete(deviceId);
    this.flushDeadlineByDevice.delete(deviceId);
  }

  private deviceKey(deviceId: string) {
    return `device:${deviceId}`;
  }

  private async ensureCacheLoaded() {
    if (this.cacheLoaded) {
      return;
    }

    const records = await this.listPersistedDeviceRecords();
    for (const record of records.values()) {
      this.recordsByDevice.set(record.device_id, record);
    }

    this.currentAlarmMs = (await this.state.storage.getAlarm()) ?? null;
    this.cacheLoaded = true;
  }

  private async listPersistedDeviceRecords() {
    this.stats.list_records_total += 1;
    return this.state.storage.list<PresenceStorageRecord>({
      prefix: "device:",
    });
  }

  private async persistRecord(record: PresenceStorageRecord) {
    this.stats.storage_puts_total += 1;
    await this.state.storage.put(this.deviceKey(record.device_id), record);
  }

  private async flushDueKeepAlive(now: number) {
    for (const [deviceId, deadline] of Array.from(
      this.flushDeadlineByDevice.entries()
    )) {
      if (deadline > now) continue;

      const record = this.recordsByDevice.get(deviceId);
      this.clearDirty(deviceId);
      if (!record) continue;

      await this.persistRecord(record);
    }
  }

  private computeNextExpiryMs() {
    let nextExpiry: number | null = null;

    for (const record of this.recordsByDevice.values()) {
      if (record.status !== "online") continue;

      const expiry = record.last_heartbeat_ms + record.ttl_ms;
      if (nextExpiry === null || expiry < nextExpiry) {
        nextExpiry = expiry;
      }
    }

    return nextExpiry;
  }

  private computeNextFlushMs() {
    let nextFlush: number | null = null;

    for (const deadline of this.flushDeadlineByDevice.values()) {
      if (nextFlush === null || deadline < nextFlush) {
        nextFlush = deadline;
      }
    }

    return nextFlush;
  }

  private computeNextAlarmMs() {
    const nextExpiry = this.computeNextExpiryMs();
    const nextFlush = this.computeNextFlushMs();

    if (nextExpiry === null) return nextFlush;
    if (nextFlush === null) return nextExpiry;
    return Math.min(nextExpiry, nextFlush);
  }

  private async setAlarmIfNeeded(target: number | null) {
    if (target === null) {
      if (this.currentAlarmMs !== null) {
        await this.state.storage.deleteAlarm();
        this.stats.delete_alarm_total += 1;
        this.currentAlarmMs = null;
      }
      return;
    }

    if (this.currentAlarmMs === null || target < this.currentAlarmMs) {
      await this.state.storage.setAlarm(target);
      this.stats.set_alarm_total += 1;
      this.currentAlarmMs = target;
    }
  }

  private async reconcileAlarm() {
    await this.setAlarmIfNeeded(this.computeNextAlarmMs());
  }

  private toStreamPayload(
    record: PresenceStorageRecord,
    sentAtMs = record.sent_at_ms
  ): PresencePayload {
    return {
      schema_version: record.schema_version,
      user_id: record.user_id,
      device_id: record.device_id,
      status: record.status,
      source: record.source,
      sent_at_ms: sentAtMs,
      seq: record.seq,
      ttl_ms: record.ttl_ms,
    };
  }

  private broadcast(payload: PresencePayload) {
    const message = encoder.encode(`data: ${JSON.stringify(payload)}\n\n`);
    for (const [id, controller] of this.streams.entries()) {
      try {
        controller.enqueue(message);
      } catch {
        this.streams.delete(id);
      }
    }
  }
}
