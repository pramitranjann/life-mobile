import Foundation
@testable import PRLifeKit

final class FakeTranscriber: Transcribing, @unchecked Sendable {
    var result: Result<String, TranscriptionError> = .success("hello")
    func transcribe(fileName: String) async throws -> String {
        switch result { case .success(let s): return s; case .failure(let e): throw e }
    }
}
