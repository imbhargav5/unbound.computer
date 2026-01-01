// ==========================================
// V1 Protocol (Legacy - Master Key Transfer)
// ==========================================

// Initiator (new device requesting pairing)
export {
  createPairingSession,
  generatePairingQR,
  getPairingQRData,
  isPairingSessionExpired,
  processPairingResponse,
  updatePairingSessionState,
} from "./initiator.js";

// QR code utilities
export {
  extractPublicKey,
  generateQRData,
  isQRDataExpired,
  parseQRData,
  serializeQRData,
} from "./qr.js";
// Responder (trusted device with Master Key)
export type { PairingResponseData } from "./responder.js";
export { createPairingResponse, validateQRCode } from "./responder.js";
export type {
  PairingQRData,
  PairingResult,
  PairingSession,
  PairingState,
} from "./types.js";

// ==========================================
// V2 Protocol (Device-Rooted Trust)
// ==========================================

// V2 Initiator (device requesting trust)
export type { CreatePairingSessionV2Options } from "./initiator-v2.js";
export {
  createPairingSessionV2,
  generatePairingQRDataV2,
  isPairingSessionV2Expired,
  processPairingResponseV2,
  serializePairingQRDataV2,
  updatePairingSessionV2State,
} from "./initiator-v2.js";

// V2 Responder (trust root device)
export type { CreatePairingResponseV2Options } from "./responder-v2.js";
export {
  createPairingResponseV2,
  extractDeviceInfoFromQR,
  parsePairingQRDataV2,
  validateQRCodeV2,
} from "./responder-v2.js";

// V2 Types
export type {
  DeviceRole,
  PairingQRDataV2,
  PairingResponseV2,
  PairingResultV2,
  PairingSessionV2,
  TrustedDeviceInfo,
} from "./types.js";
