import SwiftUI
import ThinQKit

/// The Mode, Fan, Sleep and Airflow cards in a two-column grid inside one
/// `GlassEffectContainer`, so adjacent glass blends. A card whose
/// capability the profile lacks is left out and the rest reflow; an odd last card spans both
/// columns.
struct ControlCardGrid: View {
    let snapshot: AirConditionerSnapshot
    let capabilities: AirConditionerCapabilities
    /// False while the panel is closed: the Airflow symbol stops animating.
    let isAnimating: Bool
    let send: (ACCommand) -> Void

    private enum Card: Hashable {
        case mode, fan, sleep, airflow
    }

    var body: some View {
        if !cards.isEmpty {
            GlassEffectContainer(spacing: 12) {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { card in
                                view(for: card)
                                    .gridCellColumns(row.count == 1 ? 2 : 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var cards: [Card] {
        var cards: [Card] = []
        if !capabilities.modes.isEmpty { cards.append(.mode) }
        if !capabilities.fan.options.isEmpty { cards.append(.fan) }
        if capabilities.hasSleepTimer { cards.append(.sleep) }
        if capabilities.hasVerticalSwing { cards.append(.airflow) }
        return cards
    }

    private var rows: [[Card]] {
        stride(from: 0, to: cards.count, by: 2).map { start in
            Array(cards[start..<min(start + 2, cards.count)])
        }
    }

    @ViewBuilder
    private func view(for card: Card) -> some View {
        switch card {
        case .mode: modeCard
        case .fan: fanCard
        case .sleep: sleepCard
        case .airflow: airflowCard
        }
    }

    private var modeCard: some View {
        SettingMenuCard(
            title: "Mode",
            selection: snapshot.mode,
            options: capabilities.modes,
            name: \.displayName,
            symbolName: \.symbolName,
            fallbackSymbol: "slider.horizontal.3",
            select: { send(.mode($0)) }
        )
    }

    /// Shows "Auto" / "3"; VoiceOver reads "Fan, Level 3".
    private var fanCard: some View {
        SettingMenuCard(
            title: "Fan",
            selection: snapshot.fan,
            options: capabilities.fan.options,
            name: \.displayName,
            symbolName: \.symbolName,
            fallbackSymbol: "fan",
            accessibilityValue: snapshot.fan.map(Self.fanAccessibilityValue),
            select: { send(.fan($0)) }
        )
    }

    /// Shows "Off" or the time left ("1h 20m"); picking a duration (re)starts the timer.
    private var sleepCard: some View {
        SettingMenuCard(
            title: "Sleep",
            selection: SleepTimerOption.selection(for: snapshot.sleepTimer),
            options: SleepTimerOption.all,
            name: \.displayName,
            symbolName: \.symbolName,
            fallbackSymbol: "moon.zzz",
            value: SleepTimerOption.cardValue(for: snapshot.sleepTimer),
            accessibilityValue: SleepTimerOption.accessibilityValue(for: snapshot.sleepTimer),
            select: { send($0.command) }
        )
    }

    /// Up/down swing on or off; the API has no vane angles.
    private var airflowCard: some View {
        SettingToggleCard(
            title: "Airflow",
            symbolName: "arrow.up.and.down",
            value: airflowValue,
            isOn: snapshot.verticalSwing == true,
            isAnimating: isAnimating,
            accessibilityHint: "Turns the up-and-down swing on or off.",
            toggle: { send(.verticalSwing(snapshot.verticalSwing != true)) }
        )
    }

    private var airflowValue: LocalizedStringResource {
        switch snapshot.verticalSwing {
        case true?: "Swing"
        case false?: "Fixed"
        case nil: "Unknown"
        }
    }

    private static func fanAccessibilityValue(_ setting: ACFanSetting) -> LocalizedStringResource {
        switch setting {
        case .auto: setting.displayName
        case .level(let level): "Level \(level)"
        }
    }
}
