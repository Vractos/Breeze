import Foundation
import Testing
@testable import Breeze
import ThinQKit

@Suite("Device labels")
struct DeviceLabelTests {
    private static let account = [Fixtures.arCondicionadoSala, Fixtures.arCondicionadoPraia, Fixtures.arQuarto]

    private static func device(id: String = "abcdef", model: String = "MODEL", alias: String) -> DeviceSummary {
        DeviceSummary(id: id, deviceType: DeviceSummary.airConditionerType, modelName: model, alias: alias)
    }

    @Test func sameAliasIsDisambiguatedByModelAndIDSuffix() {
        let labels = DeviceLabel.labels(for: Self.account, nicknames: [:])

        #expect(labels.map(\.id) == Self.account.map(\.id))
        #expect(labels.map(\.name) == ["Ar-condicionado", "Ar-condicionado", "Ar Quarto"])
        #expect(labels.map(\.isAmbiguous) == [true, true, false])
        #expect(labels[0].fullName == "Ar-condicionado · RAC_0B0001_WW · …0001")
        #expect(labels[1].fullName == "Ar-condicionado · RAC_056905_WW · …a3f2")
        #expect(labels[2].fullName == "Ar Quarto")
        #expect(labels[1].idSuffix == "…a3f2")
    }

    @Test func aNicknameReplacesTheAliasAndCanResolveTheCollision() {
        let labels = DeviceLabel.labels(
            for: Self.account,
            nicknames: [Fixtures.arCondicionadoPraia.id: "Beach house"]
        )

        #expect(labels.map(\.name) == ["Ar-condicionado", "Beach house", "Ar Quarto"])
        #expect(labels.map(\.isAmbiguous) == [false, false, false])
        #expect(labels.map(\.hasNickname) == [false, true, false])
        #expect(labels[1].lgName == "Ar-condicionado")
        #expect(labels[1].fullName == "Beach house")
    }

    @Test func aNicknameIsTrimmedAndABlankOneFallsBackToTheAlias() {
        let labels = DeviceLabel.labels(
            for: Self.account,
            nicknames: [
                Fixtures.arCondicionadoSala.id: "  Sala \n",
                Fixtures.arCondicionadoPraia.id: "   ",
            ]
        )

        #expect(labels.map(\.name) == ["Sala", "Ar-condicionado", "Ar Quarto"])
        #expect(labels.map(\.hasNickname) == [true, false, false])
    }

    @Test func aNicknameCanCollideWithAnotherAliasIgnoringCaseAndAccents() {
        let labels = DeviceLabel.labels(
            for: Self.account,
            nicknames: [
                Fixtures.arCondicionadoSala.id: "ar quártó",
                Fixtures.arCondicionadoPraia.id: "Praia",
            ]
        )

        #expect(labels.map(\.isAmbiguous) == [true, false, true])
        #expect(labels[2].fullName == "Ar Quarto · RAC_056905_WW · …e9f1")
    }

    @Test func withoutAnAliasTheModelNamesTheDeviceAndIsNotRepeated() {
        let labels = DeviceLabel.labels(
            for: [Self.device(id: "id-1111", alias: ""), Self.device(id: "id-2222", alias: " ")],
            nicknames: [:]
        )

        #expect(labels.map(\.name) == ["MODEL", "MODEL"])
        #expect(labels.map(\.isAmbiguous) == [true, true])
        #expect(labels[0].fullName == "MODEL · …1111")
    }

    @Test func withoutAliasOrModelTheGenericNameIsUsed() {
        let labels = DeviceLabel.labels(for: [Self.device(id: "ab", model: "", alias: "")], nicknames: [:])

        #expect(labels.first?.name == String(localized: "Air conditioner"))
        #expect(labels.first?.idSuffix == "…ab")
    }

    @Test func aSingleDeviceIsNeverAmbiguous() {
        let labels = DeviceLabel.labels(for: [Fixtures.arCondicionadoSala], nicknames: [:])

        #expect(labels.first?.isAmbiguous == false)
        #expect(labels.first?.fullName == "Ar-condicionado")
    }
}
