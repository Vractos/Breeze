#if DEBUG
import SwiftUI

/// Puts a scenario's store, settings and login item into a preview's environment:
/// `#Preview(traits: .modifier(PreviewScenarioModifier(.ready))) { PanelView() }`.
///
/// Gotcha: the store loads asynchronously, and the preview canvas snapshots the first frame,
/// so a `.task` that runs the scenario is too late (the snapshot shows "Connecting…").
/// `makeSharedContext()` is awaited before any preview renders, so every scenario is fully
/// prepared there, once, and shared by all previews that use this modifier.
struct PreviewScenarioModifier: PreviewModifier {
    let scenario: PreviewScenario

    init(_ scenario: PreviewScenario) {
        self.scenario = scenario
    }

    static func makeSharedContext() async throws -> [PreviewScenario: PreviewEnvironment] {
        var environments: [PreviewScenario: PreviewEnvironment] = [:]
        for scenario in PreviewScenario.allCases {
            let environment = PreviewEnvironment(scenario: scenario)
            await scenario.prepare(environment.store)
            environments[scenario] = environment
        }
        return environments
    }

    @ViewBuilder
    func body(content: Content, context: [PreviewScenario: PreviewEnvironment]) -> some View {
        if let environment = context[scenario] {
            content
                .environment(environment.store)
                .environment(environment.settings)
                .environment(environment.loginItem)
        } else {
            Text(verbatim: "Missing preview scenario")
        }
    }
}
#endif
