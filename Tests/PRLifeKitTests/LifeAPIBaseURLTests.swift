import XCTest
@testable import PRLifeKit

final class LifeAPIBaseURLTests: XCTestCase {
    func test_normalizedURL_acceptsHTTPSHostWithoutScheme() {
        let url = LifeAPIBaseURL.normalizedURL(from: "www.pramitranjan.com")
        XCTAssertEqual(url?.absoluteString, "https://www.pramitranjan.com")
    }

    func test_normalizedURL_prefersHTTPForLocalhostWithoutScheme() {
        let url = LifeAPIBaseURL.normalizedURL(from: "localhost:3000")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000")
    }

    func test_normalizedURL_acceptsPrivateLANHostWithoutScheme() {
        let url = LifeAPIBaseURL.normalizedURL(from: "192.168.1.8:3000")
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.8:3000")
    }

    func test_normalizedURL_rejectsUnsupportedScheme() {
        XCTAssertNil(LifeAPIBaseURL.normalizedURL(from: "ftp://example.com"))
    }

    func test_allowsInsecureHTTP_onlyForLocalHosts() {
        XCTAssertTrue(LifeAPIBaseURL.allowsInsecureHTTP(URL(string: "http://localhost:3000")!))
        XCTAssertTrue(LifeAPIBaseURL.allowsInsecureHTTP(URL(string: "http://192.168.1.8:3000")!))
        XCTAssertFalse(LifeAPIBaseURL.allowsInsecureHTTP(URL(string: "http://example.com")!))
    }
}
