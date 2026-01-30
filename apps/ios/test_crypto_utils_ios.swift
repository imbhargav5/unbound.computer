#!/usr/bin/env swift
import Foundation
import CryptoKit

// MARK: - Type Definitions

enum PairwiseContext: String {
    case session = "unbound-session-v1"
    case message = "unbound-message-v1"
    case webSession = "unbound-web-session-v1"
}

enum CryptoError: Error {
    case invalidKeySize
    case invalidNonceSize
    case decryptionFailed
    case invalidPublicKey
    case invalidPrivateKey
}

// MARK: - CryptoUtils Implementation

struct CryptoUtils {
    static func validateKeySize(_ data: Data) throws {
        guard data.count == 32 else {
            throw CryptoError.invalidKeySize
        }
    }

    static func validateNonceSize(_ data: Data) throws {
        guard data.count == 12 else {
            throw CryptoError.invalidNonceSize
        }
    }

    static func validatePublicKeySize(_ data: Data) throws {
        guard data.count == 32 else {
            throw CryptoError.invalidPublicKey
        }
    }

    static func validatePrivateKeySize(_ data: Data) throws {
        guard data.count == 32 else {
            throw CryptoError.invalidPrivateKey
        }
    }

    static func buildKeyDerivationInfo(context: PairwiseContext, identifier: String) -> String {
        "\(context.rawValue):\(identifier)"
    }

    static func buildMessageKeyInfo(purpose: String, counter: UInt64) -> String {
        "\(PairwiseContext.message.rawValue):\(purpose):\(counter)"
    }

    static func orderDeviceIds(_ id1: String, _ id2: String) -> (smaller: String, larger: String) {
        id1 < id2 ? (id1, id2) : (id2, id1)
    }

    static func keyToData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    static func dataToBase64(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func base64ToData(_ base64: String) -> Data? {
        Data(base64Encoded: base64)
    }

    static func splitCiphertextAndTag(_ combined: Data) throws -> (ciphertext: Data, tag: Data) {
        let tagSize = 16
        guard combined.count >= tagSize else {
            throw CryptoError.decryptionFailed
        }
        let ciphertext = combined.prefix(combined.count - tagSize)
        let tag = combined.suffix(tagSize)
        return (ciphertext, tag)
    }

    static func combineCiphertextAndTag(ciphertext: Data, tag: Data) -> Data {
        ciphertext + tag
    }

    static func parseEncryptedMessage(_ combined: Data) throws -> (nonce: Data, ciphertext: Data) {
        guard combined.count > 28 else {  // 12 nonce + 16 tag minimum
            throw CryptoError.invalidNonceSize
        }
        let nonce = combined.prefix(12)
        let ciphertext = combined.dropFirst(12)
        return (nonce, ciphertext)
    }

    static func combineEncryptedMessage(nonce: Data, ciphertext: Data) -> Data {
        nonce + ciphertext
    }

    static func dataToHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func hexToData(_ hex: String) -> Data? {
        var data = Data()
        var hex = hex

        hex = hex.replacingOccurrences(of: " ", with: "")
        hex = hex.replacingOccurrences(of: "0x", with: "")

        guard hex.count % 2 == 0 else { return nil }

        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        return data
    }
}

// MARK: - Test Runner

print("🧪 Testing CryptoUtils")
print("======================\n")

// Test 1: Validate valid key size (32 bytes)
print("Test 1: Validate Valid Key Size")
print("-------------------------------")
let validKey = Data(repeating: 0, count: 32)
do {
    try CryptoUtils.validateKeySize(validKey)
    print("  ✓ 32-byte key validated successfully")
} catch {
    fatalError("Should not throw for 32-byte key")
}
print("  ✅ PASSED\n")

// Test 2: Validate invalid key size
print("Test 2: Validate Invalid Key Size")
print("---------------------------------")
let invalidKey = Data(repeating: 0, count: 16)
do {
    try CryptoUtils.validateKeySize(invalidKey)
    fatalError("Should throw for 16-byte key")
} catch CryptoError.invalidKeySize {
    print("  ✓ Correctly rejected 16-byte key")
} catch {
    fatalError("Wrong error type")
}
print("  ✅ PASSED\n")

// Test 3: Validate valid nonce size (12 bytes)
print("Test 3: Validate Valid Nonce Size")
print("---------------------------------")
let validNonce = Data(repeating: 0, count: 12)
do {
    try CryptoUtils.validateNonceSize(validNonce)
    print("  ✓ 12-byte nonce validated successfully")
} catch {
    fatalError("Should not throw for 12-byte nonce")
}
print("  ✅ PASSED\n")

// Test 4: Validate invalid nonce size
print("Test 4: Validate Invalid Nonce Size")
print("-----------------------------------")
let invalidNonce = Data(repeating: 0, count: 8)
do {
    try CryptoUtils.validateNonceSize(invalidNonce)
    fatalError("Should throw for 8-byte nonce")
} catch CryptoError.invalidNonceSize {
    print("  ✓ Correctly rejected 8-byte nonce")
} catch {
    fatalError("Wrong error type")
}
print("  ✅ PASSED\n")

// Test 5: Build key derivation info
print("Test 5: Build Key Derivation Info")
print("---------------------------------")
let sessionInfo = CryptoUtils.buildKeyDerivationInfo(context: .session, identifier: "session-123")
let messageInfo = CryptoUtils.buildKeyDerivationInfo(context: .message, identifier: "msg-456")
let webInfo = CryptoUtils.buildKeyDerivationInfo(context: .webSession, identifier: "web-789")

assert(sessionInfo == "unbound-session-v1:session-123", "Session info should match")
assert(messageInfo == "unbound-message-v1:msg-456", "Message info should match")
assert(webInfo == "unbound-web-session-v1:web-789", "Web info should match")

print("  ✓ Session: \(sessionInfo)")
print("  ✓ Message: \(messageInfo)")
print("  ✓ Web: \(webInfo)")
print("  ✅ PASSED\n")

// Test 6: Build message key info with counter
print("Test 6: Build Message Key Info")
print("------------------------------")
let msgKey0 = CryptoUtils.buildMessageKeyInfo(purpose: "encrypt", counter: 0)
let msgKey1 = CryptoUtils.buildMessageKeyInfo(purpose: "encrypt", counter: 1)
let msgKey100 = CryptoUtils.buildMessageKeyInfo(purpose: "encrypt", counter: 100)

assert(msgKey0 == "unbound-message-v1:encrypt:0", "Counter 0 should match")
assert(msgKey1 == "unbound-message-v1:encrypt:1", "Counter 1 should match")
assert(msgKey100 == "unbound-message-v1:encrypt:100", "Counter 100 should match")

print("  ✓ Counter 0: \(msgKey0)")
print("  ✓ Counter 1: \(msgKey1)")
print("  ✓ Counter 100: \(msgKey100)")
print("  ✅ PASSED\n")

// Test 7: Order device IDs (lexicographic)
print("Test 7: Order Device IDs")
print("------------------------")
let (smaller1, larger1) = CryptoUtils.orderDeviceIds("device-aaa", "device-zzz")
let (smaller2, larger2) = CryptoUtils.orderDeviceIds("device-zzz", "device-aaa")

assert(smaller1 == "device-aaa" && larger1 == "device-zzz", "Should order correctly")
assert(smaller2 == "device-aaa" && larger2 == "device-zzz", "Order should be consistent")

print("  ✓ Ordered pair 1: (\(smaller1), \(larger1))")
print("  ✓ Ordered pair 2: (\(smaller2), \(larger2))")
print("  ✓ Both produce same ordering")
print("  ✅ PASSED\n")

// Test 8: Base64 encoding/decoding
print("Test 8: Base64 Encoding/Decoding")
print("--------------------------------")
let originalData = "Hello, World!".data(using: .utf8)!
let encoded = CryptoUtils.dataToBase64(originalData)
let decoded = CryptoUtils.base64ToData(encoded)!

assert(decoded == originalData, "Round-trip should preserve data")
print("  ✓ Original: Hello, World!")
print("  ✓ Encoded: \(encoded)")
print("  ✓ Decoded matches original")
print("  ✅ PASSED\n")

// Test 9: Invalid Base64 decoding
print("Test 9: Invalid Base64 Decoding")
print("-------------------------------")
let invalidBase64 = "This is not valid base64!!!"
let result = CryptoUtils.base64ToData(invalidBase64)
assert(result == nil, "Invalid base64 should return nil")
print("  ✓ Invalid base64 correctly rejected")
print("  ✅ PASSED\n")

// Test 10: Split ciphertext and tag
print("Test 10: Split Ciphertext and Tag")
print("---------------------------------")
let ciphertext = Data([1, 2, 3, 4, 5])
let tag = Data([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
let combined = ciphertext + tag

let (splitCipher, splitTag) = try! CryptoUtils.splitCiphertextAndTag(combined)
assert(splitCipher == ciphertext, "Ciphertext should match")
assert(splitTag == tag, "Tag should match")

print("  ✓ Ciphertext length: \(splitCipher.count)")
print("  ✓ Tag length: \(splitTag.count)")
print("  ✅ PASSED\n")

// Test 11: Split invalid data (too short)
print("Test 11: Split Invalid Data")
print("---------------------------")
let tooShort = Data([1, 2, 3])  // Less than 16 bytes
do {
    let _ = try CryptoUtils.splitCiphertextAndTag(tooShort)
    fatalError("Should throw for data shorter than tag")
} catch CryptoError.decryptionFailed {
    print("  ✓ Correctly rejected data shorter than tag")
} catch {
    fatalError("Wrong error type")
}
print("  ✅ PASSED\n")

// Test 12: Combine ciphertext and tag
print("Test 12: Combine Ciphertext and Tag")
print("-----------------------------------")
let cipher = Data([1, 2, 3, 4, 5])
let tagData = Data([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
let combinedData = CryptoUtils.combineCiphertextAndTag(ciphertext: cipher, tag: tagData)

assert(combinedData.prefix(5) == cipher, "First 5 bytes should be ciphertext")
assert(combinedData.suffix(16) == tagData, "Last 16 bytes should be tag")
assert(combinedData.count == 21, "Total length should be 21")

print("  ✓ Combined length: \(combinedData.count)")
print("  ✅ PASSED\n")

// Test 13: Parse encrypted message (nonce + ciphertext)
print("Test 13: Parse Encrypted Message")
print("--------------------------------")
let nonce = Data(repeating: 1, count: 12)
let message = Data(repeating: 2, count: 20)
let encrypted = nonce + message

let (parsedNonce, parsedMessage) = try! CryptoUtils.parseEncryptedMessage(encrypted)
assert(parsedNonce == nonce, "Nonce should match")
assert(parsedMessage == message, "Message should match")

print("  ✓ Nonce length: \(parsedNonce.count)")
print("  ✓ Message length: \(parsedMessage.count)")
print("  ✅ PASSED\n")

// Test 14: Parse invalid encrypted message (too short)
print("Test 14: Parse Invalid Encrypted Message")
print("----------------------------------------")
let tooShortMsg = Data(repeating: 0, count: 20)  // Less than 28 bytes
do {
    let _ = try CryptoUtils.parseEncryptedMessage(tooShortMsg)
    fatalError("Should throw for message shorter than 28 bytes")
} catch CryptoError.invalidNonceSize {
    print("  ✓ Correctly rejected short message")
} catch {
    fatalError("Wrong error type")
}
print("  ✅ PASSED\n")

// Test 15: Combine encrypted message
print("Test 15: Combine Encrypted Message")
print("----------------------------------")
let nonceData = Data(repeating: 1, count: 12)
let ciphertextData = Data(repeating: 2, count: 20)
let combined15 = CryptoUtils.combineEncryptedMessage(nonce: nonceData, ciphertext: ciphertextData)

assert(combined15.prefix(12) == nonceData, "First 12 bytes should be nonce")
assert(combined15.dropFirst(12) == ciphertextData, "Remaining bytes should be ciphertext")
assert(combined15.count == 32, "Total length should be 32")

print("  ✓ Combined length: \(combined15.count)")
print("  ✅ PASSED\n")

// Test 16: Hex encoding
print("Test 16: Hex Encoding")
print("--------------------")
let hexData = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
let hexString = CryptoUtils.dataToHex(hexData)
assert(hexString == "0123456789abcdef", "Hex encoding should be lowercase")

print("  ✓ Encoded: \(hexString)")
print("  ✅ PASSED\n")

// Test 17: Hex decoding
print("Test 17: Hex Decoding")
print("--------------------")
let hexInput = "0123456789abcdef"
let decodedHex = CryptoUtils.hexToData(hexInput)!
assert(decodedHex == Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]), "Hex decoding should work")

print("  ✓ Decoded \(decodedHex.count) bytes")
print("  ✅ PASSED\n")

// Test 18: Hex decoding with 0x prefix
print("Test 18: Hex Decoding with 0x Prefix")
print("------------------------------------")
let hexWithPrefix = "0x1234"
let decoded18 = CryptoUtils.hexToData(hexWithPrefix)!
assert(decoded18 == Data([0x12, 0x34]), "Should handle 0x prefix")

print("  ✓ Decoded with prefix: \(decoded18.count) bytes")
print("  ✅ PASSED\n")

// Test 19: Hex decoding with spaces
print("Test 19: Hex Decoding with Spaces")
print("---------------------------------")
let hexWithSpaces = "01 23 45 67"
let decoded19 = CryptoUtils.hexToData(hexWithSpaces)!
assert(decoded19 == Data([0x01, 0x23, 0x45, 0x67]), "Should handle spaces")

print("  ✓ Decoded with spaces: \(decoded19.count) bytes")
print("  ✅ PASSED\n")

// Test 20: Invalid hex decoding (odd length)
print("Test 20: Invalid Hex Decoding")
print("-----------------------------")
let oddLengthHex = "123"  // Odd number of characters
let invalidResult = CryptoUtils.hexToData(oddLengthHex)
assert(invalidResult == nil, "Odd-length hex should return nil")

print("  ✓ Odd-length hex correctly rejected")
print("  ✅ PASSED\n")

// Summary
print("======================")
print("🎉 ALL TESTS PASSED!")
print("======================")
print("\n✅ CryptoUtils is working correctly!\n")
print("Test Summary:")
print("  ✓ Key size validation (valid and invalid)")
print("  ✓ Nonce size validation (valid and invalid)")
print("  ✓ Key derivation info building")
print("  ✓ Message key info with counters")
print("  ✓ Device ID ordering (lexicographic)")
print("  ✓ Base64 encoding/decoding")
print("  ✓ Ciphertext/tag splitting and combining")
print("  ✓ Encrypted message parsing and combining")
print("  ✓ Hex encoding/decoding (with prefixes and spaces)")
print("  ✓ Error handling for invalid inputs")
print("\nReady for production! 🚀")
