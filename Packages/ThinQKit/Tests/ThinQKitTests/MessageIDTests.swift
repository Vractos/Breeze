import Foundation
import Testing
@testable import ThinQKit

@Suite("x-message-id")
struct MessageIDTests {
    private static let urlSafeAlphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    @Test func isTwentyTwoURLSafeCharactersWithoutPadding() {
        for _ in 0..<200 {
            let id = ThinQMessageID.make()
            #expect(id.count == 22)
            #expect(id.allSatisfy { Self.urlSafeAlphabet.contains($0) })
            #expect(!id.contains("="))
        }
    }

    @Test func decodesBackToSixteenBytes() throws {
        let id = ThinQMessageID.make()
        let standard = id.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "=="
        let bytes = try #require(Data(base64Encoded: standard))
        #expect(bytes.count == 16)
    }

    @Test func isUniquePerCall() {
        let ids = (0..<1000).map { _ in ThinQMessageID.make() }
        #expect(Set(ids).count == ids.count)
    }
}
