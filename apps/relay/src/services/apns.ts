/**
 * APNs (Apple Push Notification Service) client
 *
 * Uses HTTP/2 with JWT-based token authentication for sending push notifications
 * to iOS devices and updating Live Activities.
 */

import * as crypto from "node:crypto";
import * as http2 from "node:http2";
import { config } from "../config.js";
import { createLogger } from "../utils/index.js";

const log = createLogger({ module: "apns" });

// APNs endpoints
const APNS_HOST_PRODUCTION = "api.push.apple.com";
const APNS_HOST_SANDBOX = "api.sandbox.push.apple.com";

// JWT token lifetime (max 1 hour, we use 55 minutes for safety margin)
const TOKEN_LIFETIME_MS = 55 * 60 * 1000;

/**
 * APNs push types
 * - alert: Standard push notification (wakes app)
 * - background: Silent push (content-available)
 * - liveactivity: Live Activity update
 */
type ApnsPushType = "alert" | "background" | "liveactivity";

/**
 * APNs notification priority
 * - 10: Send immediately (for user-facing alerts)
 * - 5: Send when convenient (for background updates)
 */
type ApnsPriority = 5 | 10;

/**
 * APNs notification payload
 */
interface ApnsPayload {
  aps: {
    alert?: {
      title?: string;
      subtitle?: string;
      body?: string;
    };
    badge?: number;
    sound?: string;
    "content-available"?: 1;
    "mutable-content"?: 1;
    "thread-id"?: string;
    "interruption-level"?: "passive" | "active" | "time-sensitive" | "critical";
    "relevance-score"?: number;
    // Live Activity specific
    event?: "start" | "update" | "end";
    "content-state"?: Record<string, unknown>;
    timestamp?: number;
    "stale-date"?: number;
    "dismissal-date"?: number;
    "attributes-type"?: string;
    attributes?: Record<string, unknown>;
  };
  // Custom payload data
  [key: string]: unknown;
}

/**
 * Result of sending an APNs notification
 */
interface ApnsSendResult {
  success: boolean;
  apnsId?: string;
  statusCode?: number;
  reason?: string;
  timestamp?: number;
}

/**
 * APNs Service for sending push notifications
 */
class ApnsService {
  private privateKey: crypto.KeyObject | null = null;
  private cachedToken: string | null = null;
  private tokenExpiry = 0;
  private http2Sessions: Map<string, http2.ClientHttp2Session> = new Map();

  /**
   * Check if APNs is configured and available
   */
  get isConfigured(): boolean {
    return !!(
      config.APNS_KEY_ID &&
      config.APNS_TEAM_ID &&
      config.APNS_PRIVATE_KEY
    );
  }

  /**
   * Initialize the APNs service
   */
  initialize(): boolean {
    if (!this.isConfigured) {
      log.info("APNs not configured - push notifications disabled");
      return false;
    }

    try {
      // Decode base64 private key
      const keyContent = Buffer.from(
        config.APNS_PRIVATE_KEY!,
        "base64"
      ).toString("utf-8");
      this.privateKey = crypto.createPrivateKey(keyContent);
      log.info("APNs service initialized successfully");
      return true;
    } catch (error) {
      log.error({ error }, "Failed to initialize APNs private key");
      return false;
    }
  }

  /**
   * Generate or return cached JWT token for APNs authentication
   */
  private getToken(): string {
    const now = Date.now();

    // Return cached token if still valid
    if (this.cachedToken && now < this.tokenExpiry) {
      return this.cachedToken;
    }

    if (!this.privateKey) {
      throw new Error("APNs private key not initialized");
    }

    // Create JWT header and payload
    const header = {
      alg: "ES256",
      kid: config.APNS_KEY_ID!,
    };

    const payload = {
      iss: config.APNS_TEAM_ID!,
      iat: Math.floor(now / 1000),
    };

    // Sign the token
    const headerB64 = Buffer.from(JSON.stringify(header)).toString("base64url");
    const payloadB64 = Buffer.from(JSON.stringify(payload)).toString(
      "base64url"
    );
    const signatureInput = `${headerB64}.${payloadB64}`;

    const signature = crypto
      .createSign("SHA256")
      .update(signatureInput)
      .sign(this.privateKey);

    // Convert DER signature to raw format for JWT
    const rawSignature = this.derToRaw(signature);
    const signatureB64 = rawSignature.toString("base64url");

    this.cachedToken = `${signatureInput}.${signatureB64}`;
    this.tokenExpiry = now + TOKEN_LIFETIME_MS;

    log.debug("Generated new APNs JWT token");
    return this.cachedToken;
  }

  /**
   * Convert DER-encoded signature to raw format (r || s)
   */
  private derToRaw(derSignature: Buffer): Buffer {
    // DER format: 0x30 [total-length] 0x02 [r-length] [r] 0x02 [s-length] [s]
    let offset = 2; // Skip 0x30 and total length

    // Read r
    offset++; // Skip 0x02
    let rLength = derSignature[offset++];
    if (rLength === 33 && derSignature[offset] === 0) {
      // Skip leading zero padding
      offset++;
      rLength = 32;
    }
    const r = derSignature.subarray(offset, offset + 32);
    offset += rLength > 32 ? rLength : 32;

    // Read s
    offset++; // Skip 0x02
    let sLength = derSignature[offset++];
    if (sLength === 33 && derSignature[offset] === 0) {
      offset++;
      sLength = 32;
    }
    const s = derSignature.subarray(offset, offset + 32);

    // Concatenate r and s (each padded to 32 bytes)
    const raw = Buffer.alloc(64);
    r.copy(raw, 32 - r.length);
    s.copy(raw, 64 - s.length);

    return raw;
  }

  /**
   * Get or create HTTP/2 session for APNs host
   */
  private getSession(
    environment: "sandbox" | "production"
  ): Promise<http2.ClientHttp2Session> {
    const host =
      environment === "production" ? APNS_HOST_PRODUCTION : APNS_HOST_SANDBOX;

    const existing = this.http2Sessions.get(host);
    if (existing && !existing.closed && !existing.destroyed) {
      return Promise.resolve(existing);
    }

    return new Promise((resolve, reject) => {
      const session = http2.connect(`https://${host}:443`);

      session.on("connect", () => {
        log.debug({ host }, "HTTP/2 session established");
        this.http2Sessions.set(host, session);
        resolve(session);
      });

      session.on("error", (error) => {
        log.error({ error, host }, "HTTP/2 session error");
        this.http2Sessions.delete(host);
        reject(error);
      });

      session.on("close", () => {
        log.debug({ host }, "HTTP/2 session closed");
        this.http2Sessions.delete(host);
      });

      // Set timeout for connection
      setTimeout(() => {
        if (!session.connecting) return;
        session.close();
        reject(new Error("HTTP/2 connection timeout"));
      }, 10_000);
    });
  }

  /**
   * Send a push notification to a device
   */
  async send(
    deviceToken: string,
    payload: ApnsPayload,
    options: {
      environment?: "sandbox" | "production";
      pushType?: ApnsPushType;
      priority?: ApnsPriority;
      expiration?: number;
      collapseId?: string;
      topic?: string;
    } = {}
  ): Promise<ApnsSendResult> {
    if (!this.isConfigured) {
      return { success: false, reason: "APNs not configured" };
    }

    const {
      environment = "sandbox",
      pushType = "alert",
      priority = 10,
      expiration = 0,
      collapseId,
      topic = config.APNS_BUNDLE_ID,
    } = options;

    try {
      const session = await this.getSession(environment);
      const token = this.getToken();

      // Determine topic based on push type
      let apnsTopic = topic;
      if (pushType === "liveactivity") {
        apnsTopic = `${topic}.push-type.liveactivity`;
      }

      const headers: http2.OutgoingHttpHeaders = {
        ":method": "POST",
        ":path": `/3/device/${deviceToken}`,
        authorization: `bearer ${token}`,
        "apns-push-type": pushType,
        "apns-priority": priority.toString(),
        "apns-topic": apnsTopic,
      };

      if (expiration > 0) {
        headers["apns-expiration"] = expiration.toString();
      }

      if (collapseId) {
        headers["apns-collapse-id"] = collapseId;
      }

      return new Promise((resolve) => {
        const request = session.request(headers);

        const chunks: Buffer[] = [];
        let statusCode: number | undefined;
        let apnsId: string | undefined;

        request.on("response", (responseHeaders) => {
          statusCode = responseHeaders[":status"] as number;
          apnsId = responseHeaders["apns-id"] as string;
        });

        request.on("data", (chunk: Buffer) => {
          chunks.push(chunk);
        });

        request.on("end", () => {
          const body = Buffer.concat(chunks).toString("utf-8");

          if (statusCode === 200) {
            log.debug(
              { deviceToken: deviceToken.substring(0, 8), apnsId },
              "Push sent successfully"
            );
            resolve({ success: true, apnsId, statusCode });
          } else {
            let reason = "Unknown error";
            try {
              const errorBody = JSON.parse(body);
              reason = errorBody.reason || reason;
            } catch {
              reason = body || reason;
            }
            log.warn(
              { deviceToken: deviceToken.substring(0, 8), statusCode, reason },
              "Push failed"
            );
            resolve({ success: false, statusCode, reason });
          }
        });

        request.on("error", (error) => {
          log.error(
            { error, deviceToken: deviceToken.substring(0, 8) },
            "Push request error"
          );
          resolve({ success: false, reason: error.message });
        });

        request.write(JSON.stringify(payload));
        request.end();
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      log.error(
        { error, deviceToken: deviceToken.substring(0, 8) },
        "Failed to send push"
      );
      return { success: false, reason: message };
    }
  }

  /**
   * Send a silent background push to wake the app
   */
  async sendBackgroundPush(
    deviceToken: string,
    data: Record<string, unknown>,
    environment: "sandbox" | "production" = "sandbox"
  ): Promise<ApnsSendResult> {
    const payload: ApnsPayload = {
      aps: {
        "content-available": 1,
      },
      ...data,
    };

    return this.send(deviceToken, payload, {
      environment,
      pushType: "background",
      priority: 5,
    });
  }

  /**
   * Send a visible alert notification
   */
  async sendAlert(
    deviceToken: string,
    alert: { title?: string; subtitle?: string; body?: string },
    data: Record<string, unknown> = {},
    environment: "sandbox" | "production" = "sandbox"
  ): Promise<ApnsSendResult> {
    const payload: ApnsPayload = {
      aps: {
        alert,
        sound: "default",
        "interruption-level": "active",
      },
      ...data,
    };

    return this.send(deviceToken, payload, {
      environment,
      pushType: "alert",
      priority: 10,
    });
  }

  /**
   * Update a Live Activity via APNs
   */
  async updateLiveActivity(
    activityPushToken: string,
    contentState: Record<string, unknown>,
    event: "update" | "end" = "update",
    environment: "sandbox" | "production" = "sandbox",
    options: {
      staleDate?: number;
      dismissalDate?: number;
    } = {}
  ): Promise<ApnsSendResult> {
    const payload: ApnsPayload = {
      aps: {
        timestamp: Math.floor(Date.now() / 1000),
        event,
        "content-state": contentState,
      },
    };

    if (options.staleDate) {
      payload.aps["stale-date"] = options.staleDate;
    }

    if (options.dismissalDate) {
      payload.aps["dismissal-date"] = options.dismissalDate;
    }

    return this.send(activityPushToken, payload, {
      environment,
      pushType: "liveactivity",
      priority: 10,
    });
  }

  /**
   * Close all HTTP/2 sessions
   */
  shutdown(): void {
    for (const [host, session] of this.http2Sessions) {
      log.debug({ host }, "Closing HTTP/2 session");
      session.close();
    }
    this.http2Sessions.clear();
  }
}

// Singleton instance
export const apnsService = new ApnsService();
