import ThinQKit

nonisolated extension PropertySpec.NumericRange {
    /// Profiles without a step accept any value in range; the controls still need one.
    static let fallbackStep = 0.5

    /// The step the slider and the −/+ buttons use.
    var effectiveStep: Double {
        step ?? Self.fallbackStep
    }

    /// Whether the slider can show this range (SwiftUI's `Slider` needs `min < max`).
    var isAdjustable: Bool {
        max > min
    }

    /// The next allowed value one step above (`up == true`) or below `current`: on the step grid
    /// that starts at `min`, clamped to `min…max`, skipping `except` values. Returns the clamped
    /// `current` when there is nowhere to go.
    func value(steppingFrom current: Double, up: Bool) -> Double {
        let start = Swift.min(Swift.max(current, min), max)
        var candidate = start
        // Bounded: the grid has at most (max - min) / step points; `except` lists are tiny.
        for _ in 0..<Self.maximumSkips {
            let next = neighbour(of: candidate, up: up)
            guard next != candidate else { return start }
            candidate = next
            if !isExcluded(candidate) { return candidate }
        }
        return start
    }

    /// The adjacent grid point strictly above/below `value` (an off-grid value such as 24.5 on a
    /// whole-degree grid moves to 25 / 24, not 25.5), clamped to the range.
    private func neighbour(of value: Double, up: Bool) -> Double {
        let stepSize = effectiveStep
        let position = (value - min) / stepSize
        let index = up
            ? (position + Self.tolerance).rounded(.down) + 1
            : (position - Self.tolerance).rounded(.up) - 1
        let raw = min + index * stepSize
        return snapped(Swift.min(Swift.max(raw, min), max))
    }

    private func isExcluded(_ value: Double) -> Bool {
        except.contains { abs($0 - value) < Self.tolerance }
    }

    private static let tolerance = 1e-6
    private static let maximumSkips = 64
}
