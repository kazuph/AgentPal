import Foundation

/// One line of `agentpal usage`.
public struct UsageTextRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case claude, codex, openCodeGo
    }

    public let label: String
    public let bucket: CodexUsageBucket?
    public let observedAt: Date?
    public let kind: Kind

    public init(label: String, bucket: CodexUsageBucket?, observedAt: Date?, kind: Kind) {
        self.label = label
        self.bucket = bucket
        self.observedAt = observedAt
        self.kind = kind
    }

    /// Claude weekly, Claude 5h (only while Claude Code reports it), each per-model
    /// weekly limit, Codex weekly, then OpenCode Go weekly when this Mac has a Go
    /// key.
    public static func rows(
        codex: CodexUsageSnapshot?,
        claude: ClaudeUsageSnapshot?,
        openCodeGo: OpenCodeGoUsageReader.Result = .notConfigured
    ) -> [UsageTextRow] {
        var rows = [
            UsageTextRow(label: "Claude W", bucket: claude?.sevenDay, observedAt: claude.map { $0.sevenDayObservedAt ?? $0.observedAt }, kind: .claude),
        ]
        // 5時間の上限が無いプラン（Ultra）では Claude Code が five_hour を出さないので、行ごと出さない。
        if let claude, let fiveHour = claude.fiveHour {
            rows.append(UsageTextRow(label: "Claude 5h", bucket: fiveHour, observedAt: claude.fiveHourObservedAt ?? claude.observedAt, kind: .claude))
        }
        for modelLimit in claude?.modelLimits ?? [] {
            rows.append(UsageTextRow(label: "\(modelLimit.displayName) W", bucket: modelLimit.bucket, observedAt: modelLimit.observedAt, kind: .claude))
        }
        rows.append(UsageTextRow(label: "Codex W", bucket: codex?.weekly, observedAt: codex?.observedAt, kind: .codex))
        switch openCodeGo {
        case .notConfigured:
            break
        case .unavailable:
            rows.append(UsageTextRow(label: "Go W", bucket: nil, observedAt: nil, kind: .openCodeGo))
        case let .snapshot(go):
            rows.append(UsageTextRow(label: "Go W", bucket: go.weekly, observedAt: go.observedAt, kind: .openCodeGo))
        }
        return rows
    }
}

/// Renders the usage rows as text bars for terminals (ikesu's sidebar plugin):
/// the colored part is what is left, │ is the even pace for the time left,
/// red marks use beyond the pace and green the room under it.
public enum UsageTextRenderer {
    /// The labels share one column as wide as the longest label plus a space.
    public static func labelWidth(for rows: [UsageTextRow]) -> Int {
        (rows.map(\.label.count).max() ?? 0) + 1
    }

    public static func render(rows: [UsageTextRow], width: Int, color: Bool, now: Date = Date()) -> String {
        let labelWidth = labelWidth(for: rows)
        return rows.map { line(for: $0, width: width, labelWidth: labelWidth, color: color, now: now) }.joined(separator: "\n")
    }

    public static func line(for row: UsageTextRow, width: Int, labelWidth: Int, color: Bool, now: Date = Date()) -> String {
        let label = row.label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
        guard let bucket = row.bucket else {
            return label + paint("----", .dim, color)
        }
        let remaining = bucket.remainingPercent
        let percent = String(format: "%3d%%", Int(remaining.rounded()))
        let barWidth = max(4, width - labelWidth - 1 - percent.count)
        let pace = bucket.paceRemainingPercent(at: row.observedAt ?? now)
        let difference = UsagePaceDifference.between(remaining: remaining, pace: pace)
        let marker = pace.map { min(barWidth - 1, max(0, Int($0 / 100 * Double(barWidth)))) }
        var bar = ""
        for index in 0..<barWidth {
            let position = (Double(index) + 0.5) / Double(barWidth) * 100
            if index == marker {
                bar += paint("│", .marker, color)
                continue
            }
            if let difference, position >= difference.lower, position < difference.upper {
                bar += paint("█", difference.kind == .overuse ? .overuse : .surplus, color)
            } else if position < remaining {
                bar += paint("█", tone(for: row.kind), color)
            } else {
                bar += paint(color ? "░" : "·", .dim, color)
            }
        }
        return label + bar + " " + percent
    }

    static func tone(for kind: UsageTextRow.Kind) -> Tone {
        switch kind {
        case .claude: return .claude
        case .codex: return .codex
        case .openCodeGo: return .openCodeGo
        }
    }

    enum Tone {
        case claude, codex, openCodeGo, overuse, surplus, marker, dim

        var sgr: String {
            switch self {
            case .claude: return "38;2;217;119;87"
            case .codex: return "38;2;108;158;248"
            case .openCodeGo: return "38;2;200;160;255"
            case .overuse: return "38;2;229;72;77"
            case .surplus: return "38;2;70;196;110"
            case .marker: return "1;38;2;240;240;240"
            case .dim: return "38;2;110;110;110"
            }
        }
    }

    static func paint(_ text: String, _ tone: Tone, _ color: Bool) -> String {
        color ? "\u{1B}[\(tone.sgr)m\(text)\u{1B}[0m" : text
    }
}
