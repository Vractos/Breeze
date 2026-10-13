import Testing

/// Parent of every `ACStore` suite. Serialized because the store tests share the main actor and
/// use short real-time waits to let tasks settle; running them one at a time keeps that reliable.
@Suite(.serialized)
@MainActor
struct StoreTests {}
