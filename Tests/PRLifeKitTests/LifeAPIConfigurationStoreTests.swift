import XCTest
@testable import PRLifeKit

final class LifeAPIConfigurationStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-config-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_load_returnsNil_whenNoFile() {
        let store = FileLifeAPIConfigurationStore(directory: tempDir())
        XCTAssertNil(store.load())
    }

    func test_saveThenLoad_roundTripsTrimmedConfiguration() throws {
        let store = FileLifeAPIConfigurationStore(directory: tempDir())

        try store.save(LifeAPIConfiguration(
            baseURL: " https://example.com/app ",
            token: " secret-token "
        ))

        XCTAssertEqual(
            store.load(),
            LifeAPIConfiguration(baseURL: "https://example.com/app", token: "secret-token")
        )
    }
}
