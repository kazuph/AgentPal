import Foundation

/// One line of `agentpal usage`.
public struct UsageTextRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case claude, gemini, codex, openCodeGo
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

    /// Claude weekly, Claude 5h (only while Claude Code reports it), Gemini weekly
    /// when Antigravity CLI is configured, Codex weekly, then OpenCode Go weekly
    /// when this Mac has a Go key.
    public static func rows(
        codex: CodexUsageSnapshot?,
        claude: ClaudeUsageSnapshot?,
        antigravity: AntigravityUsageReader.Result = .notConfigured,
        openCodeGo: OpenCodeGoUsageReader.Result = .notConfigured
    ) -> [UsageTextRow] {
        var rows = [
            UsageTextRow(label: "Claude W", bucket: claude?.sevenDay, observedAt: claude.map { $0.sevenDayObservedAt ?? $0.observedAt }, kind: .claude),
        ]
        // 5時間の上限が無いプラン（Ultra）では Claude Code が five_hour を出さないので、行ごと出さない。
        if let claude, let fiveHour = claude.fiveHour {
            rows.append(UsageTextRow(label: "Claude 5h", bucket: fiveHour, observedAt: claude.fiveHourObservedAt ?? claude.observedAt, kind: .claude))
        }
        switch antigravity {
        case .notConfigured:
            break
        case .unavailable:
            rows.append(UsageTextRow(label: "Gemini W", bucket: nil, observedAt: nil, kind: .gemini))
        case let .snapshot(gemini):
            rows.append(UsageTextRow(label: "Gemini W", bucket: gemini.weekly, observedAt: gemini.observedAt, kind: .gemini))
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
        let paddedLabel = row.label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
        let label = paint(paddedLabel, labelTone(for: row.kind), color)
        guard let bucket = row.bucket else {
            return label + paint("----", .dim, color)
        }
        let remaining = bucket.remainingPercent
        let percentText = String(format: "%3d%%", Int(remaining.rounded()))
        let barWidth = max(4, width - labelWidth - 1 - percentText.count)
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
                bar += paint("█", .barBase, color)
            } else {
                bar += paint(color ? "░" : "·", .dim, color)
            }
        }
        let percent = difference?.kind == .overuse
            ? paint(percentText, .overuse, color)
            : paint(percentText, .percent, color)
        return label + bar + " " + percent
    }

    static func labelTone(for kind: UsageTextRow.Kind) -> Tone {
        switch kind {
        case .claude: return .claudeLabel
        case .gemini: return .geminiLabel
        case .codex: return .codexLabel
        case .openCodeGo: return .goLabel
        }
    }

    enum Tone {
        case claudeLabel, geminiLabel, codexLabel, goLabel
        case barBase, overuse, surplus, marker, dim, percent

        var sgr: String {
            switch self {
            case .claudeLabel: return "38;2;224;160;139" // #E0A08B soft coral
            case .geminiLabel: return "38;2;137;180;250" // #89B4FA soft blue
            case .codexLabel: return "38;2;203;166;247"  // #CBA6F7 soft purple
            case .goLabel: return "38;2;230;234;245"     // #E6EAF5 white
            case .barBase: return "38;2;104;114;148"     // #687294 unified slate
            case .overuse: return "38;2;247;118;142"     // #F7768E Tokyo Night red
            case .surplus: return "38;2;115;218;202"     // #73DACA Tokyo Night mint
            case .marker: return "1;38;2;224;230;255"    // #E0E6FF crisp white
            case .dim: return "38;2;74;80;104"           // #4A5068 muted track
            case .percent: return "38;2;169;177;214"     // #A9B1D6 Tokyo Night subtext
            }
        }
    }

    static func paint(_ text: String, _ tone: Tone, _ color: Bool) -> String {
        color ? "\u{1B}[\(tone.sgr)m\(text)\u{1B}[0m" : text
    }
}
