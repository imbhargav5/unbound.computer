import { generateKeyPair, randomBytes, toBase64, toHex } from "@unbound/crypto";
import type { DeviceIdentity, DeviceInfo, DeviceType } from "./types.js";
import { DeviceInfoSchema } from "./types.js";

/**
 * Generate a unique device fingerprint
 * Based on random bytes - stable per device registration
 */
export function generateFingerprint(): string {
  const bytes = randomBytes(16);
  return toHex(bytes);
}

/**
 * Generate a new device ID
 */
export function generateDeviceId(): string {
  return crypto.randomUUID();
}

/**
 * Create a new device identity
 */
export function createDeviceIdentity(
  name: string,
  type: DeviceType,
  fingerprint?: string
): DeviceIdentity {
  const keyPair = generateKeyPair();
  return {
    id: generateDeviceId(),
    name,
    type,
    fingerprint: fingerprint ?? generateFingerprint(),
    publicKey: keyPair.publicKey,
    createdAt: new Date(),
  };
}

/**
 * Serialize device identity to transportable format
 */
export function serializeDeviceIdentity(device: DeviceIdentity): DeviceInfo {
  return {
    id: device.id,
    name: device.name,
    type: device.type,
    fingerprint: device.fingerprint,
    publicKey: toBase64(device.publicKey),
    createdAt: device.createdAt.toISOString(),
  };
}

/**
 * Validate device info
 */
export function validateDeviceInfo(data: unknown): DeviceInfo {
  return DeviceInfoSchema.parse(data);
}

/**
 * Detect the current device type based on platform
 */
export function detectDeviceType(): DeviceType {
  if (typeof process !== "undefined" && process.platform) {
    switch (process.platform) {
      case "darwin":
        return "mac";
      case "linux":
        return "linux";
      case "win32":
        return "windows";
      default:
        return "linux";
    }
  }

  // Browser/React Native detection
  if (typeof navigator !== "undefined") {
    const ua = navigator.userAgent.toLowerCase();
    if (ua.includes("iphone") || ua.includes("ipad")) {
      return "ios";
    }
    if (ua.includes("android")) {
      return "android";
    }
    if (ua.includes("mac")) {
      return "mac";
    }
    if (ua.includes("win")) {
      return "windows";
    }
  }

  return "linux";
}

/**
 * Get a default device name based on type and hostname
 */
export function getDefaultDeviceName(
  type: DeviceType,
  hostname?: string
): string {
  if (hostname) {
    return hostname;
  }

  switch (type) {
    case "mac":
      return "Mac";
    case "linux":
      return "Linux";
    case "windows":
      return "Windows";
    case "ios":
      return "iPhone";
    case "android":
      return "Android";
    default:
      return "Device";
  }
}
