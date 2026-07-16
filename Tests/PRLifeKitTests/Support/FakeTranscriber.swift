import Foundation
@testable import PRLifeKit

final class FakeTranscriber: Transcribing, @unchecked Sendable {
    var result: Result<String, TranscriptionError> = .success("hello")
    private(set) var callCount = 0
    func transcribe(fileName: String) async throws -> String {
        callCount += 1
        switch result { case .success(let s): return s; case .failure(let e): throw e }
    }
}
