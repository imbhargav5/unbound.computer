/**
 * Web Session types
 */

export const WEB_SESSION_STATUS = {
  PENDING: "pending",
  ACTIVE: "active",
  EXPIRED: "expired",
  REVOKED: "revoked",
} as const;

export type WebSessionStatus =
  (typeof WEB_SESSION_STATUS)[keyof typeof WEB_SESSION_STATUS];

/**
 * Web session expiration times
 */
export const WEB_SESSION_EXPIRY = {
  /** Pending sessions expire after 5 minutes */
  PENDING_MINUTES: 5,
  /** Active sessions expire after 24 hours */
  ACTIVE_HOURS: 24,
} as const;

/**
 * QR code data for web session authorization
 */
export interface WebSessionQRData {
  version: number;
  type: "web-session";
  sessionId: string;
  publicKey: string;
  expiresAt: number;
  timestamp: number;
}

/**
 * Web session init response
 */
export interface WebSessionInitResponse {
  sessionId: string;
  qrData: string;
  expiresAt: string;
}

/**
 * Web session status response
 */
export interface WebSessionStatusResponse {
  id: string;
  status: WebSessionStatus;
  createdAt: string;
  expiresAt: string;
  authorizedAt: string | null;
  encryptedSessionKey: string | null;
  responderPublicKey: string | null;
  authorizingDevice: {
    id: string;
    name: string;
    deviceType: string;
  } | null;
}

/**
 * Authorization request from trusted device
 */
export interface WebSessionAuthorizeRequest {
  deviceId: string;
  encryptedSessionKey: string;
  responderPublicKey: string;
}
