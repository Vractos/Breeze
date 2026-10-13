import Testing
import ThinQKit
@testable import thinq

@Suite("CLI output, backoff and failures")
struct CLIBehaviourTests {
    @Test func leavesAddressUnitTaggedEntriesByUnit() {
        let state: JSONValue = [
            "operation": ["airConOperationMode": "POWER_ON"],
            "temperatureInUnits": [
                ["unit": "F", "targetTemperature": 72],
                ["unit": "C", "targetTemperature": 22.5],
            ],
            "list": [1, 2],
        ]
        #expect(CLIOutput.leaves(of: state) == [
            "operation.airConOperationMode": #""POWER_ON""#,
            "temperatureInUnits[F].unit": #""F""#,
            "temperatureInUnits[F].targetTemperature": "72",
            "temperatureInUnits[C].unit": #""C""#,
            "temperatureInUnits[C].targetTemperature": "22.5",
            "list[0]": "1",
            "list[1]": "2",
        ])
    }

    @Test func backoffDoublesUpToFifteenMinutes() {
        #expect(CLIRunner.backoffInterval(after: 120, everySeconds: 120) == 240)
        #expect(CLIRunner.backoffInterval(after: 480, everySeconds: 120) == 900)
        #expect(CLIRunner.backoffInterval(after: 900, everySeconds: 120) == 900)
    }

    @Test func backoffNeverPollsFasterThanConfigured() {
        // --every 1800 used to drop to 900 s on the first 1306.
        #expect(CLIRunner.backoffInterval(after: 1800, everySeconds: 1800) == 1800)
        #expect(CLIRunner.backoffInterval(after: 1000, everySeconds: 1000) == 1000)
        let maximum = CLICommand.maximumWatchInterval
        #expect(CLIRunner.backoffInterval(after: maximum, everySeconds: maximum) == maximum)
    }

    @Test func powerOffErrorOnOtherCommandsTellsTheUserToTurnItOn() {
        let failure = CLIFailure.api(.api(code: .commandNotSupportedInPowerOff, message: ""))
        #expect(failure.description.contains("thinq set <deviceId> power on"))
        #expect(failure.exitCode == 1)
    }
}
