import XCTest
@testable import LoviginAnalytics

private actor Recorder {
    var requests: [URLRequest] = []
    var failFirst = false
    init(failFirst: Bool = false) { self.failFirst = failFirst }
    func send(_ request: URLRequest) throws {
        requests.append(request)
        if failFirst { failFirst = false; throw URLError(.notConnectedToInternet) }
    }
    func captured() -> [URLRequest] { requests }
}

final class LoviginAnalyticsTests: XCTestCase {
    private let token = "cm12345678901234567890." + String(repeating: "a", count: 43)

    func testBatchesOnlyAllowlistedScreensWithNoIdentifiers() async throws {
        let recorder = Recorder()
        let sdk = try XCTUnwrap(LoviginAnalytics(token: token, screens: ["home", "settings"], send: { try await recorder.send($0) }))
        await sdk.trackScreen("home")
        await sdk.trackScreen("home")
        await sdk.trackScreen("alice@example.com")
        await sdk.flush()
        let requests = await recorder.captured()
        XCTAssertEqual(requests.count, 1)
        let request = requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.analytics.lovigin.com/v1/aggregate")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let rows = try XCTUnwrap(body["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["path"] as? String, "/home")
        XCTAssertEqual(rows[0]["count"] as? Int, 2)
        XCTAssertEqual(Set(body.keys), ["siteId", "batchId", "rows"])
        XCTAssertEqual(Set(rows[0].keys), ["day", "path", "count", "event", "label", "source", "country", "device"])
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("alice"))
    }

    func testRetryKeepsBatchIDAndDoesNotMergeNewViewsIntoSentBatch() async throws {
        let recorder = Recorder(failFirst: true)
        let sdk = try XCTUnwrap(LoviginAnalytics(token: token, screens: ["home"], send: { try await recorder.send($0) }))
        await sdk.trackScreen("home")
        await sdk.flush()
        await sdk.trackScreen("home")
        await sdk.flush()
        await sdk.flush()
        let requests = await recorder.captured()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        XCTAssertNotEqual(requests[1].httpBody, requests[2].httpBody)
    }

    func testOptOutClearsUnsentCounts() async throws {
        let recorder = Recorder()
        let sdk = try XCTUnwrap(LoviginAnalytics(token: token, screens: ["home"], send: { try await recorder.send($0) }))
        await sdk.trackScreen("home")
        await sdk.setCollectionEnabled(false)
        await sdk.trackScreen("home")
        await sdk.flush()
        let requests = await recorder.captured()
        XCTAssertTrue(requests.isEmpty)
    }

    func testInvalidConfigurationDisablesSDK() {
        XCTAssertNil(LoviginAnalytics(token: "invalid", screens: ["home"]))
        XCTAssertNil(LoviginAnalytics(token: token, screens: ["alice@example.com"]))
        XCTAssertNil(LoviginAnalytics(token: token, screens: []))
    }

    func testSplitsMoreThanOneHundredRowsWithoutLosingCounts() async throws {
        let recorder = Recorder()
        let names = Set((0..<150).map { "screen-\($0)" })
        let sdk = try XCTUnwrap(LoviginAnalytics(token: token, screens: names, send: { try await recorder.send($0) }))
        for name in names { await sdk.trackScreen(name) }
        await sdk.flush()
        await sdk.flush()
        let requests = await recorder.captured()
        XCTAssertEqual(requests.count, 2)
        var total = 0
        for request in requests {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let rows = try XCTUnwrap(body["rows"] as? [[String: Any]])
            XCTAssertLessThanOrEqual(rows.count, 100)
            total += rows.count
        }
        XCTAssertEqual(total, 150)
    }
}
