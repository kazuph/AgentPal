import XCTest
@testable import AgentPalCore

final class UsageTextTests: XCTestCase {
    func testRowsFollowStatusBarOrder() {
        let observed = Date(timeIntervalSince1970: 1_000)
        let week = CodexUsageBucket(label: "W", usedPercent: 60, windowSeconds: 100, resetAt: 1_050)
        let claude = ClaudeUsageSnapshot(
            fiveHour: nil, sevenDay: week,
            modelLimits: [ClaudeModelUsageLimit(displayName: "Fable", bucket: week, observedAt: observed)],
            fiveHourObservedAt: nil, sevenDayObservedAt: observed, observedAt: observed, source: "test")
        let rows = UsageTextRow.rows(codex: nil, claude: claude)
        XCTAssertEqual(rows.map(\.label), ["CC W", "CC 5h", "FAB W", "CX W"])
        XCTAssertNil(rows[1].bucket)
        XCTAssertTrue(rows[3].isCodex)
    }

    func testPlainLineShowsRemainingPaceAndPercent() {
        // 残り40%、目安50%（残り時間が半分）: 0〜40% が塗られ、40〜50% が使いすぎ、50% に │。
        let bucket = CodexUsageBucket(label: "W", usedPercent: 60, windowSeconds: 100, resetAt: 1_050)
        let row = UsageTextRow(label: "CC W", bucket: bucket, observedAt: Date(timeIntervalSince1970: 1_000), isCodex: false)
        let line = UsageTextRenderer.line(for: row, width: 21, color: false)
        XCTAssertEqual(line, "CC W  █████│····  40%")
        XCTAssertTrue(UsageTextRenderer.line(for: row, width: 21, color: true).contains("\u{1B}[38;2;229;72;77m"))
    }

    func testUnknownBucketShowsDashes() {
        let row = UsageTextRow(label: "CX W", bucket: nil, observedAt: nil, isCodex: true)
        XCTAssertEqual(UsageTextRenderer.line(for: row, width: 25, color: false), "CX W  ----")
    }
}
