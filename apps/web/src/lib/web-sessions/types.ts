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
  expiresAt: number;
  publicKey: string;
  sessionId: string;
  timestamp: number;
  type: "web-session";
  version: number;
}

/**
 * Web session init response
 */
export interface WebSessionInitResponse {
  expiresAt: string;
  qrData: string;
  sessionId: string;
}

/**
 * Web session status response
 */
export interface WebSessionStatusResponse {
  authorizedAt: string | null;
  authorizingDevice: {
    id: string;
    name: string;
    deviceType: string;
  } | null;
  createdAt: string;
  encryptedSessionKey: string | null;
  expiresAt: string;
  id: string;
  responderPublicKey: string | null;
  status: WebSessionStatus;
}

/**
 * Authorization request from trusted device
 */
export interface WebSessionAuthorizeRequest {
  deviceId: string;
  encryptedSessionKey: string;
  responderPublicKey: string;
}
