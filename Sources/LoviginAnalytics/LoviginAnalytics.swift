import Foundation

/// Aggregate screen counts. No visitor, installation, session, advertising, or device identifier.
public actor LoviginAnalytics {
    public static let version = "0.1.1"
    private struct Row: Encodable, Sendable {
        let day: String
        let path: String
        var count: Int
        let event = "page_view"
        let label = ""
        let source = "direct"
        let country = "ZZ"
        let device = "unknown"
    }
    private struct Batch: Encodable, Sendable {
        let siteId: String
        let batchId: String
        let rows: [Row]
    }
    typealias Sender = @Sendable (URLRequest) async throws -> Void
    private let siteId: String
    private let ingestKey: String
    private let screens: Set<String>
    private let send: Sender
    private var enabled = true
    private var pending: [String: Row] = [:]
    private var batch: Batch?
    private var failures = 0
    private var sending = false
    private var timer: Task<Void, Never>?

    /// The token is a public, write-only ingestion credential in a distributed app.
    /// Use the app's dedicated iOS stream token. Never pass an owner/session or Web stream token.
    /// Returns nil for invalid configuration so analytics cannot prevent app startup.
    public init?(token: String, screens: Set<String>) {
        guard let credentials = Self.credentials(token), Self.validScreens(screens) else { return nil }
        self.siteId = credentials.0
        self.ingestKey = credentials.1
        self.screens = screens
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration)
        self.send = { request in
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }
    }

    init?(token: String, screens: Set<String>, send: @escaping Sender) {
        guard let credentials = Self.credentials(token), Self.validScreens(screens) else { return nil }
        self.siteId = credentials.0
        self.ingestKey = credentials.1
        self.screens = screens
        self.send = send
    }

    private static func credentials(_ token: String) -> (String, String)? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].range(of: "^c[a-z0-9]{20,35}$", options: .regularExpression) != nil,
              parts[1].range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func validScreens(_ screens: Set<String>) -> Bool {
        !screens.isEmpty && screens.count <= 200 && screens.allSatisfy {
            $0.count <= 60 && $0.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil
        }
    }

    /// Count a developer-defined, allowlisted screen name, never a URL, title, email, or record ID.
    public func trackScreen(_ screen: String) {
        guard enabled, screens.contains(screen) else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.dateComponents([.year, .month, .day], from: Date())
        let day = String(format: "%04d-%02d-%02d", date.year!, date.month!, date.day!)
        let key = "\(day):\(screen)"
        guard pending.values.reduce(0, { $0 + $1.count }) < 1_000 else { return }
        if var row = pending[key] {
            row.count += 1
            pending[key] = row
        } else {
            pending[key] = Row(day: day, path: "/\(screen)", count: 1)
        }
        scheduleFlush()
    }

    /// Changes only this SDK instance's in-memory preference. Disabled collection clears unsent data.
    /// The host app may persist its own user's choice; the SDK creates no stored identifier/preference.
    public func setCollectionEnabled(_ value: Bool) {
        enabled = value
        if !value {
            pending.removeAll()
            batch = nil
            timer?.cancel()
            timer = nil
        }
    }

    private func scheduleFlush() {
        guard timer == nil, enabled else { return }
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            await self?.flush()
        }
    }

    /// Best-effort delivery; call when the app enters background. No disk queue or background task.
    public func flush() async {
        timer?.cancel()
        timer = nil
        guard enabled, !sending else { return }
        if batch == nil, !pending.isEmpty {
            let keys = pending.keys.sorted().prefix(100)
            let rows = keys.compactMap { pending[$0] }
            batch = Batch(siteId: siteId, batchId: UUID().uuidString.lowercased(), rows: rows)
            for key in keys { pending.removeValue(forKey: key) }
        }
        guard let current = batch else { return }
        sending = true
        defer { sending = false }
        var request = URLRequest(url: URL(string: "https://api.analytics.lovigin.com/v1/aggregate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ingestKey, forHTTPHeaderField: "x-lovigin-key")
        request.setValue("LoviginAnalytics-iOS/\(Self.version)", forHTTPHeaderField: "User-Agent")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(current)
            try await send(request)
            batch = nil
            failures = 0
        } catch {
            failures += 1
            if failures >= 3 { batch = nil; failures = 0 }
        }
        if enabled, batch != nil || !pending.isEmpty { scheduleFlush() }
    }
}
