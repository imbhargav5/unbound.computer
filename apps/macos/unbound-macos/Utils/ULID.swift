//
//  ULID.swift
//  unbound-macos
//
//  ULID (Universally Unique Lexicographically Sortable Identifier) generator.
//  Format: 26-character string using Crockford's Base32 encoding.
//  Structure: 10 chars timestamp (48 bits) + 16 chars random (80 bits)
//

import Foundation

enum ULID {
    /// Crockford's Base32 alphabet (excludes I, L, O, U to avoid confusion)
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generate a new ULID string
    /// - Returns: 26-character ULID string (e.g., "01ARZ3NDEKTSV4RRFFQ69G5FAV")
    static func generate() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        return generate(timestamp: timestamp)
    }

    /// Generate a ULID with a specific timestamp (useful for testing)
    /// - Parameter timestamp: Unix timestamp in milliseconds
    /// - Returns: 26-character ULID string
    static func generate(timestamp: UInt64) -> String {
        var result = ""
        result.reserveCapacity(26)

        // Encode timestamp (48 bits -> 10 characters)
        // Process 5 bits at a time from high to low
        result.append(alphabet[Int((timestamp >> 45) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 40) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 35) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 30) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 25) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 20) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 15) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 10) & 0x1F)])
        result.append(alphabet[Int((timestamp >> 5) & 0x1F)])
        result.append(alphabet[Int(timestamp & 0x1F)])

        // Generate random component (80 bits -> 16 characters)
        // Use cryptographically secure random bytes
        var randomBytes = [UInt8](repeating: 0, count: 10)
        let status = SecRandomCopyBytes(kSecRandomDefault, 10, &randomBytes)

        if status == errSecSuccess {
            // Encode 10 bytes (80 bits) as 16 base32 characters
            // Each character represents 5 bits
            result.append(alphabet[Int(randomBytes[0] >> 3)])
            result.append(alphabet[Int(((randomBytes[0] & 0x07) << 2) | (randomBytes[1] >> 6))])
            result.append(alphabet[Int((randomBytes[1] >> 1) & 0x1F)])
            result.append(alphabet[Int(((randomBytes[1] & 0x01) << 4) | (randomBytes[2] >> 4))])
            result.append(alphabet[Int(((randomBytes[2] & 0x0F) << 1) | (randomBytes[3] >> 7))])
            result.append(alphabet[Int((randomBytes[3] >> 2) & 0x1F)])
            result.append(alphabet[Int(((randomBytes[3] & 0x03) << 3) | (randomBytes[4] >> 5))])
            result.append(alphabet[Int(randomBytes[4] & 0x1F)])
            result.append(alphabet[Int(randomBytes[5] >> 3)])
            result.append(alphabet[Int(((randomBytes[5] & 0x07) << 2) | (randomBytes[6] >> 6))])
            result.append(alphabet[Int((randomBytes[6] >> 1) & 0x1F)])
            result.append(alphabet[Int(((randomBytes[6] & 0x01) << 4) | (randomBytes[7] >> 4))])
            result.append(alphabet[Int(((randomBytes[7] & 0x0F) << 1) | (randomBytes[8] >> 7))])
            result.append(alphabet[Int((randomBytes[8] >> 2) & 0x1F)])
            result.append(alphabet[Int(((randomBytes[8] & 0x03) << 3) | (randomBytes[9] >> 5))])
            result.append(alphabet[Int(randomBytes[9] & 0x1F)])
        } else {
            // Fallback to arc4random if SecRandomCopyBytes fails
            for _ in 0..<16 {
                result.append(alphabet[Int(arc4random_uniform(32))])
            }
        }

        return result
    }

    /// Validate a ULID string
    /// - Parameter ulid: String to validate
    /// - Returns: true if valid ULID format
    static func isValid(_ ulid: String) -> Bool {
        guard ulid.count == 26 else { return false }

        let validChars = CharacterSet(charactersIn: "0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        return ulid.uppercased().unicodeScalars.allSatisfy { validChars.contains($0) }
    }
}
