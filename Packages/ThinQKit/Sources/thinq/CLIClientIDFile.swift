import Foundation
import ThinQKit

/// The CLI's own persisted `x-client-id`. The sandboxed app cannot read this path, so the app
/// keeps a separate id in UserDefaults; the two register as separate clients.
enum CLIClientIDFile {
    static let relativePath = "Breeze/thinq-cli-client-id"

    /// Returns the stored id, creating the directory and a fresh id on first use.
    static func loadOrCreate() throws(CLIFailure) -> String {
        let url = try fileURL()
        if let existing = try read(url) {
            return existing
        }
        let clientID = ThinQClientID.generate()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data((clientID + "\n").utf8).write(to: url, options: .atomic)
        } catch {
            throw .configuration("Could not save the client id to \(url.path): \(error.localizedDescription)")
        }
        CLIOutput.note("Created a new ThinQ client id in \(url.path)")
        return clientID
    }

    private static func fileURL() throws(CLIFailure) -> URL {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return support.appending(path: relativePath, directoryHint: .notDirectory)
        } catch {
            throw .configuration("Could not locate Application Support: \(error.localizedDescription)")
        }
    }

    /// `nil` when the file does not exist or is empty.
    private static func read(_ url: URL) throws(CLIFailure) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            throw .configuration("Could not read the client id from \(url.path): \(error.localizedDescription)")
        }
    }
}
