import Foundation

/// OpenCode Go's allowance: the rolling 5 hours, the week and the month, each
/// as the used percent and when it resets.
public struct OpenCodeGoUsageSnapshot: Equatable, Sendable {
    public let rolling: CodexUsageBucket?
    public let weekly: CodexUsageBucket?
    public let monthly: CodexUsageBucket?
    public let observedAt: Date

    public init(rolling: CodexUsageBucket?, weekly: CodexUsageBucket?, monthly: CodexUsageBucket?, observedAt: Date) {
        self.rolling = rolling
        self.weekly = weekly
        self.monthly = monthly
        self.observedAt = observedAt
    }
}

/// Parses the body of `GET https://opencode.ai/zen/go/v1/usage`:
/// `{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"…"},"weekly":{…},"monthly":{…}}}`.
public enum OpenCodeGoUsageParser {
    public static func snapshot(from data: Data, observedAt: Date = Date()) -> OpenCodeGoUsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = object["usage"] as? [String: Any] else {
            return nil
        }
        let rolling = bucket(usage["rolling"], label: "5h") { _ in 5 * 60 * 60 }
        let weekly = bucket(usage["weekly"], label: "W") { _ in 7 * 24 * 60 * 60 }
        // 月の上限は契約日ごとに戻る。戻る日の1か月前からの長さを窓にする。
        let monthly = bucket(usage["monthly"], label: "M") { reset in
            let calendar = Calendar(identifier: .gregorian)
            guard let start = calendar.date(byAdding: .month, value: -1, to: reset) else { return nil }
            return reset.timeIntervalSince(start)
        }
        guard rolling != nil || weekly != nil || monthly != nil else { return nil }
        return OpenCodeGoUsageSnapshot(rolling: rolling, weekly: weekly, monthly: monthly, observedAt: observedAt)
    }

    static func bucket(_ value: Any?, label: String, window: (Date) -> Double?) -> CodexUsageBucket? {
        guard let meter = value as? [String: Any], let percent = (meter["percent"] as? NSNumber)?.doubleValue else {
            return nil
        }
        let reset = (meter["resetsAt"] as? String).flatMap(parseDate)
        return CodexUsageBucket(
            label: label,
            usedPercent: percent,
            windowSeconds: reset.flatMap(window),
            resetAt: reset?.timeIntervalSince1970
        )
    }

    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Reads OpenCode Go's usage with the Go key that `opencode auth login` saved.
public struct OpenCodeGoUsageReader: Sendable {
    public enum Result: Equatable, Sendable {
        /// No OpenCode Go key on this Mac: the rows are left out.
        case notConfigured
        /// A key exists but the usage could not be read: the rows show ----.
        case unavailable
        case snapshot(OpenCodeGoUsageSnapshot)
    }

    let authURL: URL
    let endpoint: URL
    let timeout: TimeInterval

    public init(
        authURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json"),
        endpoint: URL = URL(string: "https://opencode.ai/zen/go/v1/usage")!,
        timeout: TimeInterval = 5
    ) {
        self.authURL = authURL
        self.endpoint = endpoint
        self.timeout = timeout
    }

    /// The Go key in opencode's auth.json (`{"opencode-go": {"type": "api", "key": "…"}}`).
    public static func key(fromAuth data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let go = object["opencode-go"] as? [String: Any] else {
            return nil
        }
        let key = (go["key"] as? String) ?? (go["access"] as? String)
        return key?.isEmpty == false ? key : nil
    }

    public func read() async -> Result {
        guard let auth = try? Data(contentsOf: authURL), let key = Self.key(fromAuth: auth) else {
            return .notConfigured
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let snapshot = OpenCodeGoUsageParser.snapshot(from: data) else {
            return .unavailable
        }
        return .snapshot(snapshot)
    }
}
