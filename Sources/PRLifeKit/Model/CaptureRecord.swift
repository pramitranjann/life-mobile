import Foundation

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
        retryCount: Int = 0
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
    }
}
