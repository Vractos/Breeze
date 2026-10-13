import Foundation

extension FormatStyle where Self == Measurement<UnitEnergy>.FormatStyle {
    /// "13.8 kWh": one decimal, always in kWh (`usage: .asProvided` never converts to the
    /// locale's preferred energy unit). Pass a measurement already in kWh.
    static var kilowattHours: Self {
        .measurement(
            width: .abbreviated,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(1))
        )
    }

    /// VoiceOver's "13.8 kilowatt-hours".
    static var kilowattHoursWide: Self {
        .measurement(
            width: .wide,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(1))
        )
    }
}
