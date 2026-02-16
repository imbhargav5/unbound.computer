export type PresenceStatus = "online" | "offline";

export type PresenceStreamPayload = {
  schema_version: 1;
  user_id: string;
  device_id: string;
  status: PresenceStatus;
  source: string;
  sent_at_ms: number;
  seq: number;
  ttl_ms: number;
};

export type PresenceStorageRecord = {
  schema_version: 1;
  user_id: string;
  device_id: string;
  status: PresenceStatus;
  source: string;
  last_heartbeat_ms: number;
  last_offline_ms: number | null;
  updated_at_ms: number;
  seq: number;
  ttl_ms: number;
};

export type PresenceTokenResponse = {
  token: string;
  expires_at_ms: number;
  user_id: string;
  device_id: string;
  scope: string[];
};

export type PresenceErrorCode =
  | "unauthorized"
  | "forbidden"
  | "rate_limited"
  | "unavailable"
  | "invalid_payload";

export type PresenceErrorResponse = {
  error: PresenceErrorCode;
  details?: string;
  statusCode?: number;
};

export function normalizePresenceIdentifier(value: string): string {
  return value.trim().toLowerCase();
}
