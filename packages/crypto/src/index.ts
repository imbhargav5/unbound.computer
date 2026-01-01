// Types

// Encoding utilities
export {
  bytesToString,
  fromBase64,
  fromBase64Url,
  fromHex,
  stringToBytes,
  toBase64,
  toBase64Url,
  toHex,
} from "./encoding.js";
// HKDF key derivation
export { deriveKey, deriveSessionKey, generateMasterKey } from "./hkdf.js";

// Random bytes
export { randomBytes } from "./random.js";
export type { EncryptedMessage, KeyPair } from "./types.js";
export { KEY_SIZE } from "./types.js";
export type { WebSessionAuthData, WebSessionInfo } from "./web.js";
// Web session utilities
export {
  createWebSessionQRData,
  deriveWebSessionKey,
  generateSessionToken,
  hashSessionToken,
  isBrowser,
  isSecureContext,
  parseWebSessionQRData,
  sha256Hash,
} from "./web.js";
// X25519 key exchange
export {
  computeSharedSecret,
  generateKeyPair,
  getPublicKey,
} from "./x25519.js";
// XChaCha20-Poly1305 encryption
export { decrypt, decryptSealed, encrypt, encryptSealed } from "./xchacha20.js";
