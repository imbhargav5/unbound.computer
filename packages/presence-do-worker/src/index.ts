const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const uuidRegex =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

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

interface Env {
  PRESENCE_DO: DurableObjectNamespace;
  PRESENCE_DO_TOKEN_SIGNING_KEY: string;
  PRESENCE_DO_INGEST_TOKEN: string;
}

function jsonResponse(body: unknown, status: number, extraHeaders?: HeadersInit) {
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
  if (!payloadPart || !signaturePart) return null;
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
    signatureBytes,
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

function validatePresencePayload(input: unknown) {
  if (!input || typeof input !== "object") {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid JSON payload" };
  }
  const payload = input as Partial<PresencePayload>;
  if (payload.schema_version !== 1) {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid schema_version" };
  }
  const userId = normalizeIdentifier(payload.user_id ?? "");
  const deviceId = normalizeIdentifier(payload.device_id ?? "");
  if (!userId || !deviceId || !isUuid(userId) || !isUuid(deviceId)) {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid user_id or device_id" };
  }
  if (payload.user_id !== userId || payload.device_id !== deviceId) {
    return { ok: false, error: "invalid_payload" as const, details: "Identifiers must be lowercase" };
  }
  if (payload.status !== "online" && payload.status !== "offline") {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid status" };
  }
  if (typeof payload.source !== "string" || payload.source.trim().length === 0) {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid source" };
  }
  if (!Number.isFinite(payload.sent_at_ms) || (payload.sent_at_ms ?? 0) < 0) {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid sent_at_ms" };
  }
  if (!Number.isFinite(payload.seq) || (payload.seq ?? -1) < 0) {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid seq" };
  }
  if (!Number.isFinite(payload.ttl_ms) || (payload.ttl_ms ?? 0) <= 0) {
    return { ok: false, error: "invalid_payload" as const, details: "Invalid ttl_ms" };
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

    if (
      url.pathname === "/api/v1/daemon/presence/heartbeat" ||
      url.pathname === "/api/v1/mobile/presence/stream"
    ) {
      let userId = "";

      if (url.pathname === "/api/v1/mobile/presence/stream") {
        userId = normalizeIdentifier(url.searchParams.get("user_id"));
        if (!userId) {
          return jsonResponse(buildPresenceError("invalid_payload", "Missing user_id"), 400);
        }
      } else {
        try {
          const body = await request.clone().json();
          if (body && typeof body === "object" && "user_id" in body) {
            userId = normalizeIdentifier((body as { user_id?: string }).user_id);
          }
        } catch {
          return jsonResponse(buildPresenceError("invalid_payload", "Invalid JSON payload"), 400);
        }
      }

      if (!userId) {
        return jsonResponse(buildPresenceError("invalid_payload", "Missing user_id"), 400);
      }

      const id = env.PRESENCE_DO.idFromName(userId);
      const stub = env.PRESENCE_DO.get(id);
      return stub.fetch(request);
    }

    return jsonResponse(buildPresenceError("unavailable", "Route not found"), 404);
  },
} satisfies ExportedHandler<Env>;

export class PresenceDurableObject {
  private state: DurableObjectState;
  private env: Env;
  private streams = new Map<string, ReadableStreamDefaultController<Uint8Array>>();

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (url.pathname === "/api/v1/daemon/presence/heartbeat") {
      return this.handleHeartbeat(request);
    }

    if (url.pathname === "/api/v1/mobile/presence/stream") {
      return this.handleStream(request, url);
    }

    return jsonResponse(buildPresenceError("unavailable", "Route not found"), 404);
  }

  async alarm() {
    const now = Date.now();
    const records = await this.listDeviceRecords();

    for (const record of records.values()) {
      if (
        record.status === "online" &&
        now - record.last_heartbeat_ms > record.ttl_ms
      ) {
        const updated: PresenceStorageRecord = {
          ...record,
          status: "offline",
          last_offline_ms: now,
          updated_at_ms: now,
        };
        await this.state.storage.put(this.deviceKey(record.device_id), updated);
        this.broadcast(this.toStreamPayload(updated, now));
      }
    }
    await this.scheduleNextAlarm();
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
      return jsonResponse(buildPresenceError("unauthorized", "Unauthorized"), 401);
    }

    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return jsonResponse(buildPresenceError("invalid_payload", "Invalid JSON payload"), 400);
    }

    const validation = validatePresencePayload(body);
    if (!validation.ok) {
      logEvent("presence.do.heartbeat.invalid_payload", {
        reason: validation.details,
      });
      return jsonResponse(buildPresenceError(validation.error, validation.details), 400);
    }

    const payload = validation.payload;
    const recordKey = this.deviceKey(payload.device_id);
    const existing = await this.state.storage.get<PresenceStorageRecord>(recordKey);
    if (existing && payload.seq <= existing.seq) {
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
        : existing?.last_heartbeat_ms ?? payload.sent_at_ms;

    const record: PresenceStorageRecord = {
      ...payload,
      last_heartbeat_ms: lastHeartbeat,
      last_offline_ms: payload.status === "offline" ? payload.sent_at_ms : null,
      updated_at_ms: now,
    };

    await this.state.storage.put(recordKey, record);
    this.broadcast(this.toStreamPayload(record, payload.sent_at_ms));
    await this.scheduleNextAlarm();

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
      return jsonResponse(buildPresenceError("unauthorized", "Unauthorized"), 401);
    }

    const payload = await verifyPresenceToken(token, signingKey);
    if (!payload) {
      logEvent("presence.do.stream.invalid_token");
      return jsonResponse(buildPresenceError("forbidden", "Invalid token"), 403);
    }

    const now = Date.now();
    if (payload.exp_ms <= now) {
      logEvent("presence.do.stream.token_expired", { user_id: payload.user_id });
      return jsonResponse(buildPresenceError("forbidden", "Token expired"), 403);
    }

    if (!payload.scope?.includes("presence:read")) {
      logEvent("presence.do.stream.forbidden_scope", { user_id: payload.user_id });
      return jsonResponse(buildPresenceError("forbidden", "Insufficient scope"), 403);
    }

    const userId = normalizeIdentifier(url.searchParams.get("user_id"));
    if (!userId || payload.user_id !== userId) {
      logEvent("presence.do.stream.user_mismatch", {
        token_user_id: payload.user_id,
        requested_user_id: userId,
      });
      return jsonResponse(buildPresenceError("forbidden", "Token user mismatch"), 403);
    }

    const streamId = crypto.randomUUID();
    const stream = new ReadableStream<Uint8Array>({
      start: async (controller) => {
        this.streams.set(streamId, controller);
        request.signal.addEventListener("abort", () => {
          this.streams.delete(streamId);
          logEvent("presence.do.stream.disconnect", { user_id: payload.user_id });
        });

        const records = await this.listDeviceRecords();
        for (const record of records.values()) {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify(this.toStreamPayload(record, record.updated_at_ms))}\n\n`));
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

  private deviceKey(deviceId: string) {
    return `device:${deviceId}`;
  }

  private async listDeviceRecords() {
    const records = await this.state.storage.list<PresenceStorageRecord>({
      prefix: "device:",
    });
    return records;
  }

  private toStreamPayload(record: PresenceStorageRecord, sentAtMs: number): PresencePayload {
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

  private async scheduleNextAlarm() {
    const records = await this.listDeviceRecords();
    let nextAlarm: number | null = null;

    for (const record of records.values()) {
      if (record.status !== "online") continue;
      const alarmAt = record.last_heartbeat_ms + record.ttl_ms;
      if (nextAlarm === null || alarmAt < nextAlarm) {
        nextAlarm = alarmAt;
      }
    }

    if (nextAlarm !== null) {
      await this.state.storage.setAlarm(nextAlarm);
    }
  }
}
