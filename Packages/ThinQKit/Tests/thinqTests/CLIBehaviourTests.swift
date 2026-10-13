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

    @Test func fanCapabilityNamesKeysAndRawLevels() {
        let fan = FanCapability(
            levelValues: ["LOW", "LOW_MID", "MID", "MID_HIGH", "HIGH"],
            levelKey: "windStrengthDetail",
            autoKey: "windStrength"
        )
        #expect(CLIOutput.describe(fan)
            == "Auto, levels 1–5 [AUTO via airFlow.windStrength; levels via airFlow.windStrengthDetail: LOW, LOW_MID, MID, MID_HIGH, HIGH]")
        #expect(CLIOutput.describe(FanCapability.unsupported) == "not writable")
    }

    @Test func snapshotLinesIncludeTheNewControls() {
        let lines = CLIOutput.describe(AirConditionerSnapshot(
            power: .on,
            fan: .level(3),
            verticalSwing: true,
            displayLight: false,
            sleepTimer: .off
        ))
        #expect(lines.contains("Fan:     level 3"))
        #expect(lines.contains("Swing:   vertical on, horizontal —"))
        #expect(lines.contains("Light:   off"))
        #expect(lines.contains("Sleep:   off"))
        #expect(CLIOutput.describe(AirConditionerSnapshot(power: .off, fan: .auto)).contains("Fan:     Auto"))
        #expect(CLIOutput.sleepTimer(nil) == "—")
        #expect(CLIOutput.sleepTimer(.set(remaining: nil)) == "on")
        #expect(CLIOutput.sleepTimer(.set(remaining: .seconds(56 * 60))).hasSuffix(" left"))
    }

    @Test func powerOffErrorOnOtherCommandsTellsTheUserToTurnItOn() {
        let failure = CLIFailure.api(.api(code: .commandNotSupportedInPowerOff, message: ""))
        #expect(failure.description.contains("thinq set <deviceId> power on"))
        #expect(failure.exitCode == 1)
    }
}
