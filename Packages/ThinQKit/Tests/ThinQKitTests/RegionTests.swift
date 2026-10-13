import Foundation
import Testing
@testable import ThinQKit

@Suite("Region mapping")
struct RegionTests {
    @Test(arguments: [
        ("BR", ThinQRegion.aic), ("US", .aic), ("MX", .aic), ("AR", .aic),
        ("KR", .kic), ("JP", .kic), ("AU", .kic), ("IN", .kic),
        ("DE", .eic), ("GB", .eic), ("FR", .eic), ("AE", .eic), ("ZA", .eic),
    ])
    func mapsCountry(code: String, region: ThinQRegion) {
        #expect(ThinQRegion.forCountry(code) == region)
    }

    @Test func isCaseAndWhitespaceInsensitive() {
        #expect(ThinQRegion.forCountry(" br ") == .aic)
        #expect(ThinQRegion.forCountry("kr") == .kic)
    }

    @Test func unknownCountryFallsBackToDefault() {
        #expect(ThinQRegion.forCountry("ZZ") == ThinQRegion.fallback)
        #expect(ThinQRegion.forCountry("") == .aic)
        #expect(!ThinQRegion.isSupportedCountry("ZZ"))
        #expect(ThinQRegion.isSupportedCountry("BR"))
    }

    @Test func baseURLs() {
        #expect(ThinQRegion.aic.baseURL.absoluteString == "https://api-aic.lgthinq.com/")
        #expect(ThinQRegion.kic.baseURL.absoluteString == "https://api-kic.lgthinq.com/")
        #expect(ThinQRegion.eic.baseURL.absoluteString == "https://api-eic.lgthinq.com/")
    }

    @Test func configurationDerivesRegionUnlessOverridden() {
        #expect(ThinQConfiguration(accessToken: "t", countryCode: "de", clientID: "c").region == .eic)
        #expect(ThinQConfiguration(accessToken: "t", countryCode: "de", clientID: "c").countryCode == "DE")
        #expect(ThinQConfiguration(accessToken: "t", countryCode: "BR", clientID: "c", region: .kic).region == .kic)
    }

    @Test func configurationNeverPrintsTheToken() {
        let configuration = ThinQConfiguration(accessToken: "super-secret-pat", countryCode: "BR", clientID: "c")
        var dumped = ""
        dump(configuration, to: &dumped)
        #expect(!String(describing: configuration).contains("super-secret-pat"))
        #expect(!String(reflecting: configuration).contains("super-secret-pat"))
        #expect(!dumped.contains("super-secret-pat"))
    }

    @Test func clientIDIsALowercaseUUID() throws {
        let id = ThinQClientID.generate()
        #expect(UUID(uuidString: id) != nil)
        #expect(id == id.lowercased())
        #expect(ThinQClientID.generate() != id)
    }
}
