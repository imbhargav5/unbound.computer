//
//  AblyConversationMessageEnvelope.swift
//  unbound-ios
//
//  Envelope for conversation messages received via Ably realtime.
//  Mirrors the Rust ConversationPayload struct from toshinori/ably_sync.rs.
//

import Foundation

struct AblyConversationMessageEnvelope: Codable {
    let schemaVersion: Int
    let sessionId: String
    let messageId: String
    let sequenceNumber: Int64
    let senderDeviceId: String
    let createdAtMs: Int64
    let encryptionAlg: String
    let contentEncrypted: String
    let contentNonce: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionId = "session_id"
        case messageId = "message_id"
        case sequenceNumber = "sequence_number"
        case senderDeviceId = "sender_device_id"
        case createdAtMs = "created_at_ms"
        case encryptionAlg = "encryption_alg"
        case contentEncrypted = "content_encrypted"
        case contentNonce = "content_nonce"
    }

    /// Bridge to the existing decryption pipeline.
    func toEncryptedRow() -> EncryptedSessionMessageRow {
        EncryptedSessionMessageRow(
            id: messageId,
            sequenceNumber: Int(sequenceNumber),
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1000),
            contentEncrypted: contentEncrypted,
            contentNonce: contentNonce
        )
    }
}
