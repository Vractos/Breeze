import ThinQKit

/// Collects the configurations `ACStore` builds clients with.
@MainActor
final class ConfigurationRecorder {
    var configurations: [ThinQConfiguration] = []
}
