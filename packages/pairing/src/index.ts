// Types

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
