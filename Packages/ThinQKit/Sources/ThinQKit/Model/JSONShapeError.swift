/// Underlying error for `ThinQError.decoding` when JSON parsed fine but had the wrong shape
/// (e.g. `response` was an object where an array was expected).
struct JSONShapeError: Error, Sendable, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}
