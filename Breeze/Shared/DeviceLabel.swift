import Foundation
import ThinQKit

/// What the UI calls an air conditioner: the local nickname, else the LG
/// alias, else the model name. The API has no home/room data, so two ACs with the same alias in
/// different LG "homes" look identical; when display names collide, the model and the end of the
/// device id tell them apart.
nonisolated struct DeviceLabel: Identifiable, Equatable, Sendable {
    /// The device id.
    let id: String
    let name: String
    /// The name without a nickname: the alias, else the model name (Settings' placeholder).
    let lgName: String
    let modelName: String
    /// `name` is a local nickname, so it hides `lgName`.
    let hasNickname: Bool
    /// Another air conditioner on the account resolves to the same `name`.
    let isAmbiguous: Bool

    /// "…a3f2": the last four characters of the device id.
    var idSuffix: String {
        "…" + id.suffix(Self.idSuffixLength)
    }

    /// "Ar-condicionado · RAC_056905_WW · …a3f2" when ambiguous, else just `name`. The model is
    /// left out when it already is the name.
    var fullName: String {
        guard isAmbiguous else { return name }
        let model = modelName == name ? "" : modelName
        return [name, model, idSuffix]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// One label per device, in the same order. `nicknames` maps device ids to local names;
    /// blank ones are ignored.
    static func labels(for devices: [DeviceSummary], nicknames: [String: String]) -> [DeviceLabel] {
        let entries = devices.map { device in
            (device: device, nickname: trimmed(nicknames[device.id]), lgName: lgName(for: device))
        }
        let resolved = entries.map { entry in entry.nickname ?? entry.lgName }
        var counts: [String: Int] = [:]
        for name in resolved {
            counts[collisionKey(name), default: 0] += 1
        }
        return zip(entries, resolved).map { entry, name in
            DeviceLabel(
                id: entry.device.id,
                name: name,
                lgName: entry.lgName,
                modelName: entry.device.modelName,
                hasNickname: entry.nickname != nil,
                isAmbiguous: counts[collisionKey(name), default: 0] > 1
            )
        }
    }

    private static let idSuffixLength = 4

    private static func trimmed(_ nickname: String?) -> String? {
        guard let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func lgName(for device: DeviceSummary) -> String {
        if let alias = trimmed(device.alias) { return alias }
        if let model = trimmed(device.modelName) { return model }
        return String(localized: "Air conditioner")
    }

    /// "Quarto" and "quarto" (or "Sala" and "Salá") read as the same room, so they collide too.
    private static func collisionKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
