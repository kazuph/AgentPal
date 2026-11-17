import Foundation

/// One line of `agentpal usage`: the same rows the status bar image draws.
public struct UsageTextRow: Equatable, Sendable {
    public let label: String
    public let bucket: CodexUsageBucket?
    public let observedAt: Date?
    public let isCodex: Bool

    public init(label: String, bucket: CodexUsageBucket?, observedAt: Date?, isCodex: Bool) {
        self.label = label
        self.bucket = bucket
        self.observedAt = observedAt
        self.isCodex = isCodex
    }

    /// Claude Code weekly, Claude Code 5h, the first per-model weekly limit, Codex weekly.
    public static func rows(codex: CodexUsageSnapshot?, claude: ClaudeUsageSnapshot?) -> [UsageTextRow] {
        var rows = [
            UsageTextRow(label: "CC W", bucket: claude?.sevenDay, observedAt: claude.map { $0.sevenDayObservedAt ?? $0.observedAt }, isCodex: false),
            UsageTextRow(label: "CC 5h", bucket: claude?.fiveHour, observedAt: claude.map { $0.fiveHourObservedAt ?? $0.observedAt }, isCodex: false),
        ]
        if let modelLimit = claude?.modelLimits.first {
            rows.append(UsageTextRow(
                label: "\(modelLimit.displayName.prefix(3).uppercased()) W",
                bucket: modelLimit.bucket,
                observedAt: modelLimit.observedAt,
                isCodex: false
            ))
        }
        rows.append(UsageTextRow(label: "CX W", bucket: codex?.weekly, observedAt: codex?.observedAt, isCodex: true))
        return rows
    }
}

/// Renders the usage rows as text bars for terminals (ikesu's sidebar plugin):
/// the colored part is what is left, │ is the even pace for the time left,
/// red marks use beyond the pace and green the room under it.
public enum UsageTextRenderer {
    public static let labelWidth = 6

    public static func render(rows: [UsageTextRow], width: Int, color: Bool, now: Date = Date()) -> String {
        rows.map { line(for: $0, width: width, color: color, now: now) }.joined(separator: "\n")
    }

    public static func line(for row: UsageTextRow, width: Int, color: Bool, now: Date = Date()) -> String {
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
                bar += paint("█", row.isCodex ? .codex : .claude, color)
            } else {
                bar += paint(color ? "░" : "·", .dim, color)
            }
        }
        return label + bar + " " + percent
    }

    enum Tone {
        case claude, codex, overuse, surplus, marker, dim

        var sgr: String {
            switch self {
            case .claude: return "38;2;217;119;87"
            case .codex: return "38;2;108;158;248"
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
