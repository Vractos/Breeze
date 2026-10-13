import Foundation
import ThinQKit

// Entry point for `swift run thinq …`. The token only ever comes from THINQ_PAT, never a flag,
// so it stays out of shell history.

let arguments = Array(CommandLine.arguments.dropFirst())
let environment = ProcessInfo.processInfo.environment

func fail(_ failure: CLIFailure) -> Never {
    CLIOutput.error(failure.description)
    if case .usage = failure {
        CLIOutput.note("")
        CLIOutput.note(CLICommand.usage)
    }
    exit(failure.exitCode)
}

let command: CLICommand
do {
    command = try CLICommand.parse(arguments)
} catch {
    fail(error)
}

if command == .help {
    CLIOutput.line(CLICommand.usage)
    exit(0)
}

let token = environment["THINQ_PAT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
guard !token.isEmpty else {
    fail(.configuration("""
        THINQ_PAT is not set.
        Create a personal access token at https://connect-pat.lgthinq.com (tick every scope), then:
          export THINQ_PAT='<token>'
        """))
}

let country = environment["THINQ_COUNTRY"]
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    .flatMap { $0.isEmpty ? nil : $0 } ?? "BR"
if !ThinQRegion.isSupportedCountry(country) {
    CLIOutput.note("warning: THINQ_COUNTRY=\(country) is not in LG's country table; using region \(ThinQRegion.forCountry(country).rawValue).")
}

let clientID: String
do {
    clientID = try CLIClientIDFile.loadOrCreate()
} catch {
    fail(error)
}

let configuration = ThinQConfiguration(accessToken: token, countryCode: country, clientID: clientID)
let runner = CLIRunner(client: ThinQClient(configuration: configuration))
do {
    try await runner.run(command)
} catch {
    fail(error)
}
