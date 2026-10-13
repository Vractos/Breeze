import Foundation
import Observation

/// Holds the setpoint while the user is dragging the slider or pressing −/+/↑/↓, and turns a
/// burst of edits into ONE `.targetTemperature` command.
///
/// The hero reads `draft` so it follows the slider immediately; the store only hears about the
/// final value. Two ways an edit ends:
/// - −/+/↑/↓ (and slider changes outside a drag, e.g. VoiceOver): after a quiet period. Debouncing
///   uses a cancellable `Task` (no Combine, no Timer): every edit cancels the pending commit and
///   schedules a new one.
/// - A slider drag: `beginHolding()` … `endHolding(commit:)`. Edits in between only move the
///   draft, so resting the pointer mid-drag for longer than the debounce commits nothing.
@Observable
@MainActor
final class TemperatureEditor {
    static let defaultDebounce: Duration = .milliseconds(400)

    /// The value being edited, in the capability's unit; `nil` when nothing is pending.
    private(set) var draft: Double?
    /// True between `beginHolding()` and `endHolding(commit:)` (a slider drag).
    private(set) var isHolding = false

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var commitTask: Task<Void, Never>?

    init(debounce: Duration = TemperatureEditor.defaultDebounce) {
        self.debounce = debounce
    }

    /// Shows `value` at once. Outside a drag, calls `commit` with it once no further edit arrived
    /// for the debounce interval; during a drag, waits for `endHolding(commit:)`.
    func edit(to value: Double, commit: @escaping @MainActor (Double) -> Void) {
        draft = value
        cancelPendingCommit()
        guard !isHolding else { return }
        commitTask = Task { [debounce] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return  // superseded by a newer edit
            }
            // Gotcha: a task cancelled after its sleep finished, but before it got the main actor
            // back, still resumes here. Without this check an older value could be committed
            // after a newer edit.
            guard !Task.isCancelled else { return }
            self.finish(with: value, commit: commit)
        }
    }

    /// A slider drag started: keep the draft, commit nothing until `endHolding(commit:)`. A
    /// commit pending from −/+ is folded into the drag's single commit.
    func beginHolding() {
        isHolding = true
        cancelPendingCommit()
    }

    /// The drag ended: commit the draft right away (one command per drag). Nothing is committed
    /// when the drag produced no value (a click on the knob that didn't move it).
    func endHolding(commit: @MainActor (Double) -> Void) {
        isHolding = false
        cancelPendingCommit()
        guard let draft else { return }
        finish(with: draft, commit: commit)
    }

    private func cancelPendingCommit() {
        commitTask?.cancel()
        commitTask = nil
    }

    /// Clears the draft *before* committing: `ACStore.send(_:)` applies the value to the snapshot
    /// synchronously, so the hero switches from the draft to the same optimistic value in one
    /// main-actor turn and never flickers back to the old setpoint.
    private func finish(with value: Double, commit: @MainActor (Double) -> Void) {
        commitTask = nil
        draft = nil
        commit(value)
    }
}
