import Foundation

extension FormatStyle where Self == Measurement<UnitTemperature>.FormatStyle {
    /// "23 °C": the AC's own unit (`usage: .asProvided` never converts to the locale's preferred
    /// unit, so the panel shows what the AC is set to), at most one decimal (setpoints can be
    /// 24.5).
    static var acTemperature: Self {
        .measurement(
            width: .abbreviated,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...1))
        )
    }
}
