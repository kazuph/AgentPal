import Foundation

/// Antigravity CLI's Gemini quota buckets: weekly and 5-hour windows parsed from
/// the local statusline cache (`~/.gemini/antigravity-cli/cache/statusline-quota.json`).
public struct AntigravityUsageSnapshot: Equatable, Sendable {
    public let fiveHour: CodexUsageBucket?
    public let weekly: CodexUsageBucket?
    public let observedAt: Date
    public let source: String

    public init(
        fiveHour: CodexUsageBucket?,
        weekly: CodexUsageBucket?,
        observedAt: Date,
        source: String
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.observedAt = observedAt
        self.source = source
    }

    public var hasVisibleBuckets: Bool {
        fiveHour != nil || weekly != nil
    }
}

/// Parses Antigravity CLI statusline quota payloads:
/// `{"observed_at": 178..., "quota": {"gemini-5h": {"remaining_fraction": 0.9, "reset_time": "...", "reset_in_seconds": 1234}, "gemini-weekly": {...}}}`.
/// Only reads the Gemini family's weekly and 5-hour windows; other model groups
/// (such as `3p-*` or `argon`) are ignored.
public enum AntigravityUsageParser {
    public static let fiveHourWindowSeconds: Double = 5 * 60 * 60
    public static let sevenDayWindowSeconds: Double = 7 * 24 * 60 * 60

    public static func snapshot(
        from data: Data,
        observedAt: Date = Date(),
        source: String = "statusline-cache"
    ) -> AntigravityUsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return snapshot(from: object, observedAt: observedAt, source: source)
    }

    public static func snapshot(
        from object: [String: Any],
        observedAt: Date = Date(),
        source: String = "statusline-cache"
    ) -> AntigravityUsageSnapshot? {
        let effectiveObservedAt: Date
        if let recorded = number(object["observed_at"]) ?? number(object["observedAt"]) {
            effectiveObservedAt = Date(timeIntervalSince1970: recorded)
        } else {
            effectiveObservedAt = observedAt
        }
        let quota = object["quota"] as? [String: Any] ?? object

        let weekly = bucket(
            from: firstMatchingValue(
                in: quota,
                keys: ["gemini-weekly", "gemini_weekly", "gemini-7d", "gemini_7d"]
            ),
            label: "W",
            windowSeconds: sevenDayWindowSeconds,
            observedAt: effectiveObservedAt
        )
        let fiveHour = bucket(
            from: firstMatchingValue(
                in: quota,
                keys: ["gemini-5h", "gemini_5h", "gemini-5-h", "gemini-five-hour", "gemini_five_hour"]
            ),
            label: "5h",
            windowSeconds: fiveHourWindowSeconds,
            observedAt: effectiveObservedAt
        )
        guard weekly != nil || fiveHour != nil else {
            return nil
        }
        return AntigravityUsageSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            observedAt: effectiveObservedAt,
            source: source
        )
    }

    private static func firstMatchingValue(in dictionary: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = dictionary[key] {
                return value
            }
        }
        let lowered = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.lowercased(), $0.value) })
        for key in keys {
            if let value = lowered[key] {
                return value
            }
        }
        return nil
    }

    private static func bucket(
        from value: Any?,
        label: String,
        windowSeconds: Double,
        observedAt: Date
    ) -> CodexUsageBucket? {
        guard let dictionary = value as? [String: Any] else {
            return nil
        }
        if (dictionary["disabled"] as? Bool) == true {
            return nil
        }
        guard let usedPercent = usedPercent(from: dictionary) else {
            return nil
        }
        let resetAt = parseResetAt(
            resetTime: dictionary["reset_time"] ?? dictionary["resets_at"] ?? dictionary["reset_at"],
            resetInSeconds: dictionary["reset_in_seconds"] ?? dictionary["resetInSeconds"],
            observedAt: observedAt
        )
        return CodexUsageBucket(
            label: label,
            usedPercent: min(max(usedPercent, 0.0), 100.0),
            windowSeconds: windowSeconds,
            resetAt: resetAt
        )
    }

    private static func usedPercent(from dictionary: [String: Any]) -> Double? {
        if let remainingFraction = number(dictionary["remaining_fraction"]) ?? number(dictionary["remainingFraction"]) {
            let remainingPercent = remainingFraction <= 1.0 ? remainingFraction * 100.0 : remainingFraction
            return 100.0 - remainingPercent
        }
        if let used = number(dictionary["used_percentage"])
            ?? number(dictionary["used_percent"])
            ?? number(dictionary["percent"])
            ?? number(dictionary["percentage"])
        {
            return used
        }
        return nil
    }

    private static func parseResetAt(resetTime: Any?, resetInSeconds: Any?, observedAt: Date) -> Double? {
        if let epoch = number(resetTime) {
            return epoch
        }
        if let text = resetTime as? String {
            if let epoch = Double(text) {
                return epoch
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) {
                return date.timeIntervalSince1970
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) {
                return date.timeIntervalSince1970
            }
        }
        if let seconds = number(resetInSeconds), seconds >= 0 {
            return observedAt.timeIntervalSince1970 + seconds
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }
}

/// Reads Antigravity CLI's Gemini usage from the local statusline cache file.
/// AgentPal never reads Antigravity credentials or calls Google APIs directly.
public struct AntigravityUsageReader: Sendable {
    public enum Result: Equatable, Sendable {
        /// Antigravity CLI is not configured on this Mac: the Gemini row is omitted.
        case notConfigured
        /// Antigravity CLI is present, but no fresh quota cache is available: the row shows ----.
        case unavailable
        case snapshot(AntigravityUsageSnapshot)
    }

    public static let maxCacheAge: TimeInterval = 24 * 60 * 60

    let configDirectory: URL
    let cacheURL: URL
    let explicitCacheOverride: Bool

    public init(
        configDirectory: URL? = nil,
        cacheURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let defaultConfigDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli")
        let resolvedConfigDir = configDirectory ?? defaultConfigDir
        self.configDirectory = resolvedConfigDir

        if let cacheURL {
            self.cacheURL = cacheURL
            self.explicitCacheOverride = true
        } else if let override = environment["AGENTPAL_ANTIGRAVITY_USAGE_CACHE"], !override.isEmpty {
            self.cacheURL = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            self.explicitCacheOverride = true
        } else {
            self.cacheURL = resolvedConfigDir.appendingPathComponent("cache/statusline-quota.json")
            self.explicitCacheOverride = false
        }
    }

    public func read(now: Date = Date()) -> Result {
        let fileManager = FileManager.default
        let cacheExists = fileManager.fileExists(atPath: cacheURL.path)
        let configExists = explicitCacheOverride || fileManager.fileExists(atPath: configDirectory.path)
        guard cacheExists || configExists else {
            return .notConfigured
        }
        guard cacheExists,
              let attributes = try? fileManager.attributesOfItem(atPath: cacheURL.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              now.timeIntervalSince(modifiedAt) <= Self.maxCacheAge,
              let data = try? Data(contentsOf: cacheURL),
              let snapshot = AntigravityUsageParser.snapshot(
                  from: data,
                  observedAt: modifiedAt,
                  source: "statusline-cache"
              ),
              now.timeIntervalSince(snapshot.observedAt) <= Self.maxCacheAge else {
            return .unavailable
        }
        return .snapshot(snapshot)
    }
}
