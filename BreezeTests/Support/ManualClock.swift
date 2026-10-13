import Foundation
import Synchronization
@testable import Breeze

/// A `StoreClock` whose time only moves when the test calls `advance(by:)`. Sleeps suspend until
/// their deadline is reached.
final class ManualClock: StoreClock {
    private struct Sleeper: Sendable {
        let id: Int
        let deadline: Double
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State: Sendable {
        var offset: Double = 0
        var nextID = 0
        var sleepers: [Sleeper] = []
    }

    /// Whole seconds since the reference date, so `Date` arithmetic stays exact.
    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let state = Mutex(State())

    var now: Date {
        origin.addingTimeInterval(state.withLock { $0.offset })
    }

    /// Remaining time of each suspended sleeper, soonest first.
    var pendingSleeps: [Duration] {
        state.withLock { state in
            state.sleepers.map { .seconds($0.deadline - state.offset) }.sorted()
        }
    }

    func sleep(for duration: Duration) async throws {
        let seconds = duration.timeInterval
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if seconds <= 0 {
                        continuation.resume()
                    } else {
                        state.sleepers.append(Sleeper(id: id, deadline: state.offset + seconds, continuation: continuation))
                    }
                }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward, waking sleepers one deadline at a time and letting the woken tasks
    /// run (and register new sleeps) before moving on — like real time would.
    func advance(by duration: Duration) async {
        let target = state.withLock { $0.offset } + duration.timeInterval
        await settle()
        while let due = popNextSleeper(notAfter: target) {
            due.continuation.resume()
            await settle()
        }
        state.withLock { $0.offset = max($0.offset, target) }
        await settle()
    }

    private func popNextSleeper(notAfter target: Double) -> Sleeper? {
        state.withLock { state in
            let due = state.sleepers.enumerated()
                .filter { $0.element.deadline <= target }
                .min { $0.element.deadline < $1.element.deadline }
            guard let due else { return nil }
            state.sleepers.remove(at: due.offset)
            state.offset = max(state.offset, due.element.deadline)
            return due.element
        }
    }
}

/// Lets main-actor tasks and the fake API actor run until they block again.
func settle() async {
    for _ in 0..<3 {
        for _ in 0..<20 {
            await Task.yield()
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Polls `condition` (in real time) until it holds or `timeout` passes.
func waitUntil(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}
