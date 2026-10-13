import Foundation
import Testing
@testable import ThinQKit

@Suite("JSONValue")
struct JSONValueTests {
    @Test func decodesBooleansAsBooleansNotNumbers() throws {
        let value = try JSONValue(jsonData: Data(#"{"t":true,"f":false,"one":1,"half":0.5,"s":"x","n":null,"a":[1,"b"]}"#.utf8))
        #expect(value == ["t": true, "f": false, "one": 1, "half": 0.5, "s": "x", "n": nil, "a": [1, "b"]])
    }

    @Test func roundTrips() throws {
        let original: JSONValue = ["a": [1, 2.5, "three", true, nil, ["nested": [:]]]]
        let decoded = try JSONValue(jsonData: original.jsonData())
        #expect(decoded == original)
    }

    @Test func nonFiniteNumbersEncodeAsNull() throws {
        let text = String(decoding: try JSONValue.array([.number(.infinity), .number(.nan)]).jsonData(), as: UTF8.self)
        #expect(text == "[null,null]")
    }
}
