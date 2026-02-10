//
//  EncryptedSessionMessageDecoder.swift
//  unbound-ios
//
//  Parsing and decryption helpers for encrypted session message rows.
//

import CryptoKit
import Foundation

enum SessionDetailMessageError: Error, LocalizedError, Equatable {
    case fetchFailed
    case secretResolutionFailed
    case invalidEncryptedRow
    case decryptFailed
    case payloadParseFailed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Unable to fetch session messages"
        case .secretResolutionFailed:
            return "Unable to resolve session secret"
        case .invalidEncryptedRow:
            return "Session message payload is malformed"
        case .decryptFailed:
            return "Unable to decrypt session messages"
        case .payloadParseFailed:
            return "Unable to parse decrypted session message payload"
        }
    }
}

struct EncryptedSessionMessageRow {
    let id: String
    let sequenceNumber: Int
    let createdAt: Date?
    let contentEncrypted: String
    let contentNonce: String

    var stableUUID: UUID {
        if let uuid = UUID(uuidString: id) {
            return uuid
        }

        let digest = SHA256.hash(data: Data("\(id)-\(sequenceNumber)".utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func decrypt(sessionKey: Data) throws -> String {
        guard let ciphertextAndTag = Self.decodeCiphertextField(contentEncrypted) else {
            throw SessionDetailMessageError.decryptFailed
        }
        guard let nonceData = Self.decodeNonceField(contentNonce) else {
            throw SessionDetailMessageError.decryptFailed
        }
        guard ciphertextAndTag.count >= 16 else {
            throw SessionDetailMessageError.decryptFailed
        }

        let ciphertext = ciphertextAndTag.dropLast(16)
        let tag = ciphertextAndTag.suffix(16)
        let key = SymmetricKey(data: sessionKey)

        do {
            let nonce = try ChaChaPoly.Nonce(data: nonceData)
            let sealedBox = try ChaChaPoly.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )
            let plaintextData = try ChaChaPoly.open(sealedBox, using: key)
            guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
                throw SessionDetailMessageError.decryptFailed
            }

            return plaintext
        } catch {
            throw SessionDetailMessageError.decryptFailed
        }
    }

    private static func decodeCiphertextField(_ value: String) -> Data? {
        guard let raw = decodeRawBinaryField(value) else {
            return nil
        }
        if let decoded = decodeWrappedBase64IfPresent(raw), decoded.count >= 16 {
            return decoded
        }
        return raw
    }

    private static func decodeNonceField(_ value: String) -> Data? {
        guard let raw = decodeRawBinaryField(value) else {
            return nil
        }
        if raw.count == 12 {
            return raw
        }
        if let decoded = decodeWrappedBase64IfPresent(raw), decoded.count == 12 {
            return decoded
        }
        return nil
    }

    private static func decodeRawBinaryField(_ value: String) -> Data? {
        if let base64 = Data(base64Encoded: value) {
            return base64
        }

        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("\\\\x") {
            normalized.removeFirst(3)
        } else if normalized.hasPrefix("\\x") || normalized.hasPrefix("0x") {
            normalized.removeFirst(2)
        }

        guard !normalized.isEmpty, normalized.count.isMultiple(of: 2) else {
            return nil
        }

        var bytes = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }

    private static func decodeWrappedBase64IfPresent(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            return nil
        }

        if let decoded = Data(base64Encoded: text) {
            return decoded
        }

        var normalized = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        switch normalized.count % 4 {
        case 2:
            normalized += "=="
        case 3:
            normalized += "="
        default:
            break
        }
        return Data(base64Encoded: normalized)
    }
}

enum EncryptedSessionMessageDecoder {
    static func parseRows(from data: Data) throws -> [EncryptedSessionMessageRow] {
        guard let rawRows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SessionDetailMessageError.invalidEncryptedRow
        }

        return try rawRows.map(parseRow)
    }

    private static func parseRow(_ row: [String: Any]) throws -> EncryptedSessionMessageRow {
        guard let id = stringValue(row["id"]),
              let sequenceNumber = intValue(row["sequence_number"]),
              let contentEncrypted = stringValue(row["content_encrypted"]),
              let contentNonce = stringValue(row["content_nonce"]),
              !contentEncrypted.isEmpty,
              !contentNonce.isEmpty else {
            throw SessionDetailMessageError.invalidEncryptedRow
        }

        return EncryptedSessionMessageRow(
            id: id,
            sequenceNumber: sequenceNumber,
            createdAt: dateValue(row["created_at"]),
            contentEncrypted: contentEncrypted,
            contentNonce: contentNonce
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let dateString = value as? String else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}
