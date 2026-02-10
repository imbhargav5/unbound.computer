import Foundation
import XCTest

@testable import unbound_ios

final class SessionSecretFormatTests: XCTestCase {
    func testParseKeyValidSecretReturns32Bytes() throws {
        let secret = makeValidSecret(byte: 0x7A)
        let key = try SessionSecretFormat.parseKey(secret: secret)
        XCTAssertEqual(key.count, 32)
    }

    func testParseKeyRejectsInvalidPrefix() {
        XCTAssertThrowsError(try SessionSecretFormat.parseKey(secret: "invalid_secret")) { error in
            guard let parsed = error as? SessionSecretFormatError else {
                XCTFail("unexpected error type: \(error)")
                return
            }
            XCTAssertEqual(parsed, .invalidFormat)
        }
    }

    func testParseKeyRejectsMalformedPayload() {
        XCTAssertThrowsError(try SessionSecretFormat.parseKey(secret: "sess_not_base64_url")) { error in
            guard let parsed = error as? SessionSecretFormatError else {
                XCTFail("unexpected error type: \(error)")
                return
            }
            XCTAssertEqual(parsed, .malformedKey)
        }
    }

    private func makeValidSecret(byte: UInt8) -> String {
        let data = Data(repeating: byte, count: 32)
        var base64Url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while base64Url.hasSuffix("=") {
            base64Url.removeLast()
        }
        return "sess_\(base64Url)"
    }
}
