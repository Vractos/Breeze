import Testing
@testable import Breeze

/// Uses a short real debounce; `waitUntil` polls in real time.
@Suite("TemperatureEditor")
@MainActor
struct TemperatureEditorTests {
    private final class CommitLog {
        var values: [Double] = []
    }

    @Test func showsTheDraftImmediatelyAndCommitsOnceWithTheLastValue() async {
        let editor = TemperatureEditor(debounce: .milliseconds(60))
        let log = CommitLog()

        for value in [22.0, 23.0, 24.0, 25.0] {
            editor.edit(to: value) { log.values.append($0) }
            #expect(editor.draft == value)
        }
        #expect(log.values.isEmpty)

        #expect(await waitUntil { log.values == [25] })
        #expect(editor.draft == nil)
        // Nothing else arrives later from the superseded edits.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(log.values == [25])
    }

    @Test func editsSeparatedByMoreThanTheDebounceCommitSeparately() async {
        let editor = TemperatureEditor(debounce: .milliseconds(30))
        let log = CommitLog()

        editor.edit(to: 20) { log.values.append($0) }
        #expect(await waitUntil { log.values == [20] })
        editor.edit(to: 21) { log.values.append($0) }
        #expect(await waitUntil { log.values == [20, 21] })
    }

    @Test func aDragCommitsOnceWhenItEndsHoweverLongItPauses() async {
        let editor = TemperatureEditor(debounce: .milliseconds(30))
        let log = CommitLog()

        editor.beginHolding()
        editor.edit(to: 21) { log.values.append($0) }
        // The pointer rests mid-drag for well over the debounce: nothing is sent.
        try? await Task.sleep(for: .milliseconds(120))
        #expect(log.values.isEmpty)
        #expect(editor.draft == 21)

        editor.edit(to: 23) { log.values.append($0) }
        editor.endHolding { log.values.append($0) }
        #expect(log.values == [23])
        #expect(editor.draft == nil)
        #expect(!editor.isHolding)

        try? await Task.sleep(for: .milliseconds(120))
        #expect(log.values == [23])
    }

    @Test func aDragThatProducedNoValueCommitsNothing() {
        let editor = TemperatureEditor(debounce: .milliseconds(30))
        let log = CommitLog()

        editor.beginHolding()
        editor.endHolding { log.values.append($0) }

        #expect(log.values.isEmpty)
    }

    @Test func aPendingButtonEditIsFoldedIntoTheDrag() async {
        let editor = TemperatureEditor(debounce: .milliseconds(30))
        let log = CommitLog()

        editor.edit(to: 25) { log.values.append($0) }
        editor.beginHolding()
        try? await Task.sleep(for: .milliseconds(120))
        #expect(log.values.isEmpty)

        editor.endHolding { log.values.append($0) }
        #expect(log.values == [25])
    }
}
