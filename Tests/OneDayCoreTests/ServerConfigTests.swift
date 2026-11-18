import OneDayCore
import XCTest

final class ServerConfigTests: XCTestCase {
    func testBareDomainGetsHTTPS() {
        let config = ServerConfig(rawInput: "your-hermes.example.com")
        XCTAssertEqual(config?.baseString, "https://your-hermes.example.com")
    }

    func testTrailingSlashRemoved() {
        let config = ServerConfig(rawInput: "https://your-hermes.example.com/")
        XCTAssertEqual(config?.baseString, "https://your-hermes.example.com")
    }

    func testWhitespaceTrimmedAndHTTPPreserved() {
        let config = ServerConfig(rawInput: "  http://192.168.1.10:9119  ")
        XCTAssertEqual(config?.baseString, "http://192.168.1.10:9119")
    }

    func testQueryAndFragmentDropped() {
        let config = ServerConfig(rawInput: "https://your-hermes.example.com/?a=1#top")
        XCTAssertEqual(config?.baseString, "https://your-hermes.example.com")
    }

    func testEndpointBuilding() {
        let config = ServerConfig(rawInput: "your-hermes.example.com")
        XCTAssertEqual(config?.endpoint("/health").absoluteString, "https://your-hermes.example.com/health")
        XCTAssertEqual(config?.endpoint("/v1/models").absoluteString, "https://your-hermes.example.com/v1/models")
        XCTAssertEqual(config?.host, "your-hermes.example.com")
    }

    func testInvalidInputs() {
        XCTAssertNil(ServerConfig(rawInput: ""))
        XCTAssertNil(ServerConfig(rawInput: "   "))
        XCTAssertNil(ServerConfig(rawInput: "ftp://example.com"))
        XCTAssertNil(ServerConfig(rawInput: "https://"))
    }
}
