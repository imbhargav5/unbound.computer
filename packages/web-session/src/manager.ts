import {
  computeSharedSecret,
  decrypt,
  deriveKey,
  encrypt,
  fromBase64,
  generateKeyPair,
  toBase64,
} from "@unbound/crypto";
import { BrowserSessionStorage, STORAGE_KEYS } from "./storage.js";
import type {
  WebSession,
  WebSessionInitResponse,
  WebSessionOptions,
  WebSessionStatusResponse,
  WebSessionStorage,
} from "./types.js";
import {
  DEFAULT_MAX_IDLE_SECONDS,
  DEFAULT_SESSION_TTL_SECONDS,
} from "./types.js";

/**
 * Default polling interval (2 seconds)
 */
const DEFAULT_POLLING_INTERVAL = 2000;

/**
 * Default max polling attempts (150 = 5 minutes at 2s interval)
 */
const DEFAULT_MAX_POLLING_ATTEMPTS = 150;

/**
 * Idle check interval (30 seconds)
 */
const IDLE_CHECK_INTERVAL = 30_000;

/**
 * Warning time before expiry (60 seconds)
 */
const EXPIRY_WARNING_TIME = 60_000;

/**
 * WebSessionManager handles the lifecycle of a web session
 * from initialization through authorization and message encryption.
 */
/**
 * Internal options type with required fields except callbacks
 */
interface WebSessionManagerOptions {
  apiBaseUrl: string;
  pollingInterval: number;
  maxPollingAttempts: number;
  maxIdleSeconds: number;
  sessionTtlSeconds: number;
  enableIdleTimeout: boolean;
  onExpiryWarning?: () => void;
}

export class WebSessionManager {
  private session: WebSession | null = null;
  private storage: WebSessionStorage;
  private options: WebSessionManagerOptions;
  private pollingAbortController: AbortController | null = null;
  private idleCheckInterval: ReturnType<typeof setInterval> | null = null;
  private expiryWarningTimeout: ReturnType<typeof setTimeout> | null = null;
  private hasWarnedExpiry = false;

  constructor(options: WebSessionOptions) {
    this.options = {
      apiBaseUrl: options.apiBaseUrl,
      pollingInterval: options.pollingInterval ?? DEFAULT_POLLING_INTERVAL,
      maxPollingAttempts:
        options.maxPollingAttempts ?? DEFAULT_MAX_POLLING_ATTEMPTS,
      maxIdleSeconds: options.maxIdleSeconds ?? DEFAULT_MAX_IDLE_SECONDS,
      sessionTtlSeconds:
        options.sessionTtlSeconds ?? DEFAULT_SESSION_TTL_SECONDS,
      enableIdleTimeout: options.enableIdleTimeout ?? true,
      onExpiryWarning: options.onExpiryWarning,
    };

    // Use browser session storage by default
    this.storage =
      typeof sessionStorage !== "undefined"
        ? new BrowserSessionStorage()
        : new BrowserSessionStorage();
  }

  /**
   * Set custom storage adapter
   */
  setStorage(storage: WebSessionStorage): void {
    this.storage = storage;
  }

  /**
   * Initialize a new web session
   * Returns QR code data to display to the user
   */
  async initSession(): Promise<{
    sessionId: string;
    qrData: string;
    expiresAt: Date;
  }> {
    // Generate ephemeral keypair
    const ephemeralKeyPair = generateKeyPair();
    const publicKeyBase64 = toBase64(ephemeralKeyPair.publicKey);

    // Call API to create pending session
    const response = await fetch(
      `${this.options.apiBaseUrl}/api/v1/web/sessions/init`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        credentials: "include",
        body: JSON.stringify({
          publicKey: publicKeyBase64,
        }),
      }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error ?? "Failed to initialize web session");
    }

    const data: WebSessionInitResponse = await response.json();

    const now = new Date();
    // Create session object
    this.session = {
      id: data.sessionId,
      state: "waiting_for_auth",
      ephemeralKeyPair,
      sessionToken: data.sessionToken,
      createdAt: now,
      expiresAt: new Date(data.expiresAt),
      lastActivityAt: now,
      permission: "view_only", // Default, updated on authorization
      maxIdleSeconds: this.options.maxIdleSeconds,
      sessionTtlSeconds: this.options.sessionTtlSeconds,
    };

    // Store session data
    this.storage.set(STORAGE_KEYS.SESSION_ID, data.sessionId);
    this.storage.set(STORAGE_KEYS.SESSION_TOKEN, data.sessionToken);
    this.storage.set(
      STORAGE_KEYS.PRIVATE_KEY,
      toBase64(ephemeralKeyPair.privateKey)
    );
    this.storage.set(STORAGE_KEYS.EXPIRES_AT, data.expiresAt);

    return {
      sessionId: data.sessionId,
      qrData: data.qrData,
      expiresAt: new Date(data.expiresAt),
    };
  }

  /**
   * Wait for the session to be authorized by a trusted device
   * Polls the status endpoint until authorized or timeout
   */
  async waitForAuthorization(
    onStatusChange?: (status: WebSessionStatusResponse) => void
  ): Promise<void> {
    if (!this.session) {
      throw new Error("No session initialized");
    }

    this.pollingAbortController = new AbortController();

    let attempts = 0;
    while (attempts < this.options.maxPollingAttempts) {
      if (this.pollingAbortController.signal.aborted) {
        throw new Error("Authorization polling cancelled");
      }

      try {
        const status = await this.checkStatus();
        onStatusChange?.(status);

        if (status.status === "active") {
          // Session authorized - process the encrypted session key
          await this.handleAuthorization(status);
          return;
        }

        if (status.status === "expired" || status.status === "revoked") {
          this.session.state =
            status.status === "expired" ? "expired" : "error";
          this.session.error = `Session ${status.status}`;
          throw new Error(`Session ${status.status}`);
        }

        // Still pending - wait and retry
        await this.sleep(this.options.pollingInterval);
        attempts++;
      } catch (error) {
        if (error instanceof Error && error.message.includes("cancelled")) {
          throw error;
        }
        // Network error - wait and retry
        await this.sleep(this.options.pollingInterval);
        attempts++;
      }
    }

    throw new Error("Authorization timeout");
  }

  /**
   * Cancel waiting for authorization
   */
  cancelWaiting(): void {
    this.pollingAbortController?.abort();
    this.pollingAbortController = null;
  }

  /**
   * Check the current session status
   */
  async checkStatus(): Promise<WebSessionStatusResponse> {
    if (!this.session) {
      throw new Error("No session initialized");
    }

    const response = await fetch(
      `${this.options.apiBaseUrl}/api/v1/web/sessions/${this.session.id}/status`,
      {
        method: "GET",
        credentials: "include",
      }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error ?? "Failed to check session status");
    }

    return response.json();
  }

  /**
   * Handle the authorization response from the trusted device
   * Decrypts and stores the session key
   */
  private async handleAuthorization(
    status: WebSessionStatusResponse
  ): Promise<void> {
    if (!this.session) {
      throw new Error("No session initialized");
    }

    const { encryptedSessionKey, responderPublicKey, authorizingDevice } =
      status;

    if (!(encryptedSessionKey && responderPublicKey)) {
      throw new Error("Missing session key or responder public key");
    }

    try {
      // Compute shared secret with responder's public key
      const responderPubKeyBytes = fromBase64(responderPublicKey);
      const sharedSecret = computeSharedSecret(
        this.session.ephemeralKeyPair.privateKey,
        responderPubKeyBytes
      );

      // Derive decryption key
      const decryptionKey = deriveKey(
        sharedSecret,
        `web-session-auth:${this.session.id}`
      );

      // Decrypt the session key (format: nonce + ciphertext)
      const encryptedBytes = fromBase64(encryptedSessionKey);
      const nonce = encryptedBytes.slice(0, 24);
      const ciphertext = encryptedBytes.slice(24);
      const sessionKey = decrypt(decryptionKey, nonce, ciphertext);

      // Store session key and update session state
      this.session.sessionKey = sessionKey;
      this.session.state = "authorized";
      this.session.permission = status.permission;
      this.session.maxIdleSeconds = status.maxIdleSeconds;
      this.session.sessionTtlSeconds = status.sessionTtlSeconds;
      this.session.lastActivityAt = new Date();

      // Store authorizing device info
      if (authorizingDevice) {
        this.session.authorizingDevice = {
          id: authorizingDevice.id,
          name: authorizingDevice.name,
          deviceType: authorizingDevice.deviceType,
          publicKey: authorizingDevice.publicKey,
        };
      }

      // Calculate idle expiry time
      this.session.idleExpiresAt = new Date(
        Date.now() + this.session.maxIdleSeconds * 1000
      );

      this.storage.set(STORAGE_KEYS.SESSION_KEY, toBase64(sessionKey));

      // Start idle timeout checking
      if (this.options.enableIdleTimeout) {
        this.startIdleTimeoutCheck();
      }

      // Set up expiry warning
      this.setupExpiryWarning();
    } catch (error) {
      this.session.state = "error";
      this.session.error =
        error instanceof Error
          ? error.message
          : "Failed to decrypt session key";
      throw error;
    }
  }

  /**
   * Start checking for idle timeout
   */
  private startIdleTimeoutCheck(): void {
    this.stopIdleTimeoutCheck();

    this.idleCheckInterval = setInterval(() => {
      if (!this.session || this.session.state !== "authorized") {
        this.stopIdleTimeoutCheck();
        return;
      }

      const now = Date.now();
      const idleTime = now - this.session.lastActivityAt.getTime();
      const maxIdleMs = this.session.maxIdleSeconds * 1000;

      if (idleTime >= maxIdleMs) {
        this.session.state = "idle_timeout";
        this.session.error = "Session expired due to inactivity";
        this.stopIdleTimeoutCheck();
      }
    }, IDLE_CHECK_INTERVAL);
  }

  /**
   * Stop idle timeout checking
   */
  private stopIdleTimeoutCheck(): void {
    if (this.idleCheckInterval) {
      clearInterval(this.idleCheckInterval);
      this.idleCheckInterval = null;
    }
  }

  /**
   * Set up warning before session expiry
   */
  private setupExpiryWarning(): void {
    if (!(this.session && this.options.onExpiryWarning)) return;

    const timeUntilExpiry = this.session.expiresAt.getTime() - Date.now();
    const warningTime = timeUntilExpiry - EXPIRY_WARNING_TIME;

    if (warningTime > 0) {
      this.expiryWarningTimeout = setTimeout(() => {
        if (!this.hasWarnedExpiry && this.options.onExpiryWarning) {
          this.hasWarnedExpiry = true;
          this.options.onExpiryWarning();
        }
      }, warningTime);
    }
  }

  /**
   * Record activity to reset idle timeout
   */
  recordActivity(): void {
    if (!this.session || this.session.state !== "authorized") return;

    this.session.lastActivityAt = new Date();
    this.session.idleExpiresAt = new Date(
      Date.now() + this.session.maxIdleSeconds * 1000
    );
  }

  /**
   * Get time remaining until session expires (ms)
   */
  getTimeRemaining(): number {
    if (!this.session) return 0;
    return Math.max(0, this.session.expiresAt.getTime() - Date.now());
  }

  /**
   * Get time remaining until idle timeout (ms)
   */
  getIdleTimeRemaining(): number {
    if (!this.session?.idleExpiresAt) return 0;
    return Math.max(0, this.session.idleExpiresAt.getTime() - Date.now());
  }

  /**
   * Get session permission level
   */
  getPermission(): string | null {
    return this.session?.permission ?? null;
  }

  /**
   * Check if session has a specific permission
   */
  hasPermission(required: "view_only" | "interact" | "full_control"): boolean {
    if (!this.session) return false;

    const levels = { view_only: 0, interact: 1, full_control: 2 };
    return levels[this.session.permission] >= levels[required];
  }

  /**
   * Encrypt a message using the session key
   */
  encrypt(plaintext: Uint8Array): {
    nonce: Uint8Array;
    ciphertext: Uint8Array;
  } {
    if (!this.session?.sessionKey) {
      throw new Error("Session not authorized");
    }
    return encrypt(this.session.sessionKey, plaintext);
  }

  /**
   * Encrypt a message and return as base64 sealed format (nonce + ciphertext)
   */
  encryptToBase64(plaintext: Uint8Array): string {
    const { nonce, ciphertext } = this.encrypt(plaintext);
    const sealed = new Uint8Array(nonce.length + ciphertext.length);
    sealed.set(nonce);
    sealed.set(ciphertext, nonce.length);
    return toBase64(sealed);
  }

  /**
   * Decrypt a message using the session key
   */
  decrypt(nonce: Uint8Array, ciphertext: Uint8Array): Uint8Array {
    if (!this.session?.sessionKey) {
      throw new Error("Session not authorized");
    }
    return decrypt(this.session.sessionKey, nonce, ciphertext);
  }

  /**
   * Decrypt a base64 sealed message (nonce + ciphertext)
   */
  decryptFromBase64(sealed: string): Uint8Array {
    const sealedBytes = fromBase64(sealed);
    const nonce = sealedBytes.slice(0, 24);
    const ciphertext = sealedBytes.slice(24);
    return this.decrypt(nonce, ciphertext);
  }

  /**
   * Get the current session state
   */
  getState(): WebSession | null {
    return this.session;
  }

  /**
   * Check if the session is authorized
   */
  isAuthorized(): boolean {
    return this.session?.state === "authorized" && !!this.session.sessionKey;
  }

  /**
   * Check if the session has expired
   */
  isExpired(): boolean {
    if (!this.session) return true;
    return new Date() > this.session.expiresAt;
  }

  /**
   * Revoke the current session
   */
  async revoke(reason?: string): Promise<void> {
    if (!this.session) return;

    try {
      await fetch(
        `${this.options.apiBaseUrl}/api/v1/web/sessions/${this.session.id}`,
        {
          method: "DELETE",
          headers: {
            "Content-Type": "application/json",
          },
          credentials: "include",
          body: JSON.stringify({ reason }),
        }
      );
    } finally {
      this.destroy();
    }
  }

  /**
   * Restore session from storage
   */
  restoreFromStorage(): boolean {
    const sessionId = this.storage.get(STORAGE_KEYS.SESSION_ID);
    const sessionToken = this.storage.get(STORAGE_KEYS.SESSION_TOKEN);
    const privateKeyBase64 = this.storage.get(STORAGE_KEYS.PRIVATE_KEY);
    const sessionKeyBase64 = this.storage.get(STORAGE_KEYS.SESSION_KEY);
    const expiresAt = this.storage.get(STORAGE_KEYS.EXPIRES_AT);

    if (!(sessionId && sessionToken && privateKeyBase64 && expiresAt)) {
      return false;
    }

    const expiresAtDate = new Date(expiresAt);
    if (expiresAtDate < new Date()) {
      this.storage.clear();
      return false;
    }

    const privateKey = fromBase64(privateKeyBase64);
    const publicKey = new Uint8Array(32); // We don't need the public key for decryption
    const now = new Date();

    this.session = {
      id: sessionId,
      state: sessionKeyBase64 ? "authorized" : "waiting_for_auth",
      ephemeralKeyPair: { publicKey, privateKey },
      sessionToken,
      createdAt: now, // Unknown, but doesn't matter
      expiresAt: expiresAtDate,
      lastActivityAt: now,
      sessionKey: sessionKeyBase64 ? fromBase64(sessionKeyBase64) : undefined,
      permission: "view_only", // Default, will be updated on next status check
      maxIdleSeconds: this.options.maxIdleSeconds,
      sessionTtlSeconds: this.options.sessionTtlSeconds,
    };

    // If restored and authorized, start idle timeout check
    if (this.session.state === "authorized" && this.options.enableIdleTimeout) {
      this.session.idleExpiresAt = new Date(
        now.getTime() + this.session.maxIdleSeconds * 1000
      );
      this.startIdleTimeoutCheck();
    }

    return true;
  }

  /**
   * Destroy the session and clear storage
   */
  destroy(): void {
    this.cancelWaiting();
    this.stopIdleTimeoutCheck();

    if (this.expiryWarningTimeout) {
      clearTimeout(this.expiryWarningTimeout);
      this.expiryWarningTimeout = null;
    }

    this.session = null;
    this.storage.clear();
    this.hasWarnedExpiry = false;
  }

  /**
   * Touch the session to extend activity
   */
  async touch(): Promise<void> {
    if (!this.session) return;

    // Record local activity
    this.recordActivity();

    // Notify server of activity
    await fetch(
      `${this.options.apiBaseUrl}/api/v1/web/sessions/${this.session.id}`,
      {
        method: "PATCH",
        credentials: "include",
      }
    );
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
