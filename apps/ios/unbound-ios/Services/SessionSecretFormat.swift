//
//  SessionSecretFormat.swift
//  unbound-ios
//
//  Shared parser/validator for session secret strings.
//

import Foundation

enum SessionSecretFormatError: Error, LocalizedError, Equatable {
    case invalidFormat
    case malformedKey

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid session secret format"
        case .malformedKey:
            return "Session secret key is malformed"
        }
    }
}

enum SessionSecretFormat {
    private static let prefix = "sess_"

    static func parseKey(secret: String) throws -> Data {
        guard secret.hasPrefix(prefix) else {
            throw SessionSecretFormatError.invalidFormat
        }

        let base64Url = String(secret.dropFirst(prefix.count))
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        switch base64.count % 4 {
        case 2:
            base64 += "=="
        case 3:
            base64 += "="
        default:
            break
        }

        guard let keyData = Data(base64Encoded: base64), keyData.count == 32 else {
            throw SessionSecretFormatError.malformedKey
        }

        return keyData
    }
}
