import XCTest
@testable import AgentPalCore

final class UsageTextTests: XCTestCase {
    let observed = Date(timeIntervalSince1970: 1_000)
    var week: CodexUsageBucket { CodexUsageBucket(label: "W", usedPercent: 60, windowSeconds: 100, resetAt: 1_050) }

    func claude(fiveHour: CodexUsageBucket?) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fiveHour: fiveHour, sevenDay: week,
            modelLimits: [ClaudeModelUsageLimit(displayName: "Fable", bucket: week, observedAt: observed)],
            fiveHourObservedAt: nil, sevenDayObservedAt: observed, observedAt: observed, source: "test")
    }

    func testRowsUseFullNamesAndLeaveOutAMissingFiveHour() {
        let rows = UsageTextRow.rows(codex: nil, claude: claude(fiveHour: nil))
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Fable W", "Codex W"])
        XCTAssertEqual(rows[2].kind, .codex)
    }

    func testRowsKeepFiveHourWhileClaudeCodeReportsIt() {
        let rows = UsageTextRow.rows(codex: nil, claude: claude(fiveHour: week))
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Claude 5h", "Fable W", "Codex W"])
    }

    func testRowsAddOpenCodeGo() {
        let go = OpenCodeGoUsageSnapshot(rolling: week, weekly: week, monthly: nil, observedAt: observed)
        let rows = UsageTextRow.rows(codex: nil, claude: nil, openCodeGo: .snapshot(go))
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Codex W", "Go 5h", "Go W", "Go M"])
        XCTAssertNil(rows[4].bucket)
        XCTAssertEqual(UsageTextRow.rows(codex: nil, claude: nil, openCodeGo: .unavailable).map(\.label), ["Claude W", "Codex W", "Go W"])
    }

    func testPlainLineShowsRemainingPaceAndPercent() {
        // 残り40%、目安50%（残り時間が半分）: 0〜40% が塗られ、40〜50% が使いすぎ、50% に │。
        let row = UsageTextRow(label: "Claude W", bucket: week, observedAt: observed, kind: .claude)
        let line = UsageTextRenderer.line(for: row, width: 24, labelWidth: 9, color: false)
        XCTAssertEqual(line, "Claude W █████│····  40%")
        XCTAssertTrue(UsageTextRenderer.line(for: row, width: 24, labelWidth: 9, color: true).contains("\u{1B}[38;2;229;72;77m"))
    }

    func testRenderAlignsLabelsToTheLongest() {
        let rows = [
            UsageTextRow(label: "Claude W", bucket: week, observedAt: observed, kind: .claude),
            UsageTextRow(label: "Go W", bucket: nil, observedAt: nil, kind: .openCodeGo),
        ]
        let lines = UsageTextRenderer.render(rows: rows, width: 24, color: false, now: observed).split(separator: "\n")
        XCTAssertEqual(lines[1], "Go W     ----")
        XCTAssertEqual(lines[0].count, 24)
    }

    func testOpenCodeGoParserReadsAllThreeMeters() throws {
        let body = #"{"usage":{"rolling":{"status":"ok","percent":1,"resetsAt":"2026-11-17T13:00:29.000Z"},"weekly":{"status":"rate-limited","percent":100,"resetsAt":"2026-11-23T00:00:00.000Z"},"monthly":{"status":"ok","percent":0,"resetsAt":"2026-12-14T23:49:33Z"}}}"#
        let go = try XCTUnwrap(OpenCodeGoUsageParser.snapshot(from: Data(body.utf8), observedAt: observed))
        XCTAssertEqual(go.rolling?.usedPercent, 1)
        XCTAssertEqual(go.rolling?.windowSeconds, 5 * 60 * 60)
        XCTAssertEqual(go.weekly?.remainingPercent, 0)
        XCTAssertEqual(go.weekly?.windowSeconds, 7 * 24 * 60 * 60)
        // 11/14 23:49:33 から 12/14 23:49:33 までの30日。
        XCTAssertEqual(go.monthly?.windowSeconds, 30 * 24 * 60 * 60)
        XCTAssertEqual(go.monthly?.resetAt, 1_797_292_173)
        XCTAssertNil(OpenCodeGoUsageParser.snapshot(from: Data(#"{"error":"x"}"#.utf8)))
    }

    func testOpenCodeGoKeyComesFromAuthJSON() {
        XCTAssertEqual(OpenCodeGoUsageReader.key(fromAuth: Data(#"{"opencode":{"type":"api","key":"a"},"opencode-go":{"type":"api","key":"b"}}"#.utf8)), "b")
        XCTAssertNil(OpenCodeGoUsageReader.key(fromAuth: Data(#"{"opencode":{"type":"api","key":"a"}}"#.utf8)))
    }

    func testReaderWithoutAuthFileIsNotConfigured() async {
        let reader = OpenCodeGoUsageReader(authURL: URL(fileURLWithPath: "/nonexistent/auth.json"))
        let result = await reader.read()
        XCTAssertEqual(result, .notConfigured)
    }
}
