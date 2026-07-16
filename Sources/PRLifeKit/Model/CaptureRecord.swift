import Foundation

public enum CaptureRecoveryReason: String, Codable, Equatable, Sendable {
    case inputRouteLost
    case audioInterrupted

    public var message: String {
        switch self {
        case .inputRouteLost:
            return "The selected microphone disconnected. The audio captured so far was saved."
        case .audioInterrupted:
            return "Recording was interrupted. The audio captured so far was saved."
        }
    }
}

public struct CaptureRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var duration: TimeInterval
    public var context: CaptureContext
    public var audioFileName: String?     // relative to the captures directory
    public var transcript: String?
    public var status: CaptureStatus
    public var serverEntryId: String?
    public var lastError: String?
    public var retryCount: Int
    public var inputRoute: AudioInputRoute?
    public var recoveryReason: CaptureRecoveryReason?

    /// The UI can offer a new continuation capture without discarding this partial one.
    public var canResume: Bool { recoveryReason != nil }

    /// Failed transcription/upload can be retried because the original audio remains.
    public var canRetry: Bool { status == .failed && audioFileName != nil }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        context: CaptureContext,
        audioFileName: String? = nil,
        transcript: String? = nil,
        status: CaptureStatus = .recording,
        serverEntryId: String? = nil,
        lastError: String? = nil,
        retryCount: Int = 0,
        inputRoute: AudioInputRoute? = nil,
        recoveryReason: CaptureRecoveryReason? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.context = context
        self.audioFileName = audioFileName
        self.transcript = transcript
        self.status = status
        self.serverEntryId = serverEntryId
        self.lastError = lastError
        self.retryCount = retryCount
        self.inputRoute = inputRoute
        self.recoveryReason = recoveryReason
    }
}
