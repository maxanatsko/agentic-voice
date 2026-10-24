import Foundation

/// A failure with an actionable message for the user.
public struct AgenticVoiceError: Error, LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
