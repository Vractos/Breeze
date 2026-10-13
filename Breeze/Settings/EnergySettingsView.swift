import SwiftUI
import ThinQKit

/// Settings › Energy: the selected AC's energy use as LG reports it (this
/// month, today, last month and a 12-month / 30-day chart), and an optional price per kWh for
/// an estimated cost. Opening the tab is the only thing that fetches energy automatically, and
/// only when the last fetch is over an hour old.
struct EnergySettingsView: View {
    @Environment(ACStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var range: EnergyChartRange = .months

    var body: some View {
        Form {
            Section {
                usage
            } header: {
                Text("Energy Use")
            }

            Section {
                EnergyPriceField()
            } header: {
                Text("Estimated Cost")
            } footer: {
                Text("Breeze multiplies the kWh by this price. It's only an estimate: LG reports energy, not money, and tariffs, taxes and fees aren't included.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Runs when the tab appears and again when the selected AC changes (it loads after
        // launch or a switch).
        .task(id: store.device?.id) {
            await store.energyTabDidAppear()
        }
    }

    @ViewBuilder
    private var usage: some View {
        if !store.hasToken {
            Text("Save a token in the Account tab to see energy use.")
                .foregroundStyle(.secondary)
        } else if store.isEnergyUnsupported {
            Label {
                Text("This air conditioner doesn't report energy use to LG ThinQ, so Breeze can't show it.")
            } icon: {
                Image(systemName: "bolt.slash")
            }
            .foregroundStyle(.secondary)
        } else if let energy = store.energy {
            HStack(alignment: .top, spacing: 12) {
                EnergyTile(title: "This month", energy: energy.thisMonth, pricePerKWh: settings.energyPricePerKWh)
                EnergyTile(title: "Today", energy: energy.today, pricePerKWh: settings.energyPricePerKWh)
                EnergyTile(title: "Last month", energy: energy.lastMonth, pricePerKWh: settings.energyPricePerKWh)
            }
            VStack(alignment: .leading, spacing: 8) {
                Picker("Period", selection: $range) {
                    ForEach(EnergyChartRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                EnergyChart(summary: energy, range: range, pricePerKWh: settings.energyPricePerKWh)
            }
            statusRow(fetchedAt: energy.fetchedAt)
        } else {
            statusRow(fetchedAt: nil)
        }
    }

    /// "Updated 10 min ago" (or why there is nothing yet), a spinner while fetching, a failure,
    /// and Refresh.
    private func statusRow(fetchedAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Group {
                    if let fetchedAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let relative = min(fetchedAt, context.date).formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
                            Text("Updated \(relative)")
                        }
                    } else if store.isLoadingEnergy {
                        Text("Loading energy use…")
                    } else {
                        Text("No energy data loaded yet.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Spacer()
                if store.isLoadingEnergy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Loading"))
                }
                Button("Refresh", action: refresh)
                    .disabled(store.isLoadingEnergy || !store.canRefreshEnergy)
            }
            if let message = store.energyFailureMessage {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private func refresh() {
        Task { await store.refreshEnergy() }
    }
}

#if DEBUG
#Preview("Energy", traits: .modifier(PreviewScenarioModifier(.energy))) {
    EnergySettingsView()
        .frame(width: SettingsView.size.width, height: SettingsView.size.height)
}
#endif
