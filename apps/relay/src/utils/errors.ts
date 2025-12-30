/**
 * Base error class for relay errors
 */
export class RelayError extends Error {
  constructor(
    public code: string,
    message: string
  ) {
    super(message);
    this.name = "RelayError";
  }
}

/**
 * Authentication error
 */
export class AuthError extends RelayError {
  constructor(message: string) {
    super("AUTH_ERROR", message);
    this.name = "AuthError";
  }
}

/**
 * Validation error
 */
export class ValidationError extends RelayError {
  constructor(message: string) {
    super("VALIDATION_ERROR", message);
    this.name = "ValidationError";
  }
}

/**
 * Session not found error
 */
export class SessionNotFoundError extends RelayError {
  constructor(sessionId: string) {
    super("SESSION_NOT_FOUND", `Session ${sessionId} not found`);
    this.name = "SessionNotFoundError";
  }
}

/**
 * Device offline error
 */
export class DeviceOfflineError extends RelayError {
  constructor(deviceId: string) {
    super("DEVICE_OFFLINE", `Device ${deviceId} is offline`);
    this.name = "DeviceOfflineError";
  }
}

/**
 * Not authenticated error
 */
export class NotAuthenticatedError extends RelayError {
  constructor() {
    super("NOT_AUTHENTICATED", "Connection is not authenticated");
    this.name = "NotAuthenticatedError";
  }
}

/**
 * Connection timeout error
 */
export class ConnectionTimeoutError extends RelayError {
  constructor(reason: string) {
    super("CONNECTION_TIMEOUT", reason);
    this.name = "ConnectionTimeoutError";
  }
}
