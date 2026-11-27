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

    func testRowsUseFullNamesAndLeaveOutAMissingFiveHourAndModelLimits() {
        let rows = UsageTextRow.rows(codex: nil, claude: claude(fiveHour: nil))
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Codex W"])
        XCTAssertEqual(rows[1].kind, .codex)
    }

    func testRowsKeepFiveHourWhileClaudeCodeReportsIt() {
        let rows = UsageTextRow.rows(codex: nil, claude: claude(fiveHour: week))
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Claude 5h", "Codex W"])
    }

    func testRowsOrderClaudeGeminiCodexGoInFourLines() {
        let gemini = AntigravityUsageSnapshot(fiveHour: week, weekly: week, observedAt: observed, source: "test")
        let go = OpenCodeGoUsageSnapshot(rolling: week, weekly: week, monthly: nil, observedAt: observed)
        let rows = UsageTextRow.rows(
            codex: CodexUsageSnapshot(shortTerm: nil, weekly: week, monthly: nil, observedAt: observed, source: "test"),
            claude: claude(fiveHour: nil),
            antigravity: .snapshot(gemini),
            openCodeGo: .snapshot(go)
        )
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Gemini W", "Codex W", "Go W"])
        XCTAssertEqual(rows.map(\.kind), [.claude, .gemini, .codex, .openCodeGo])
        XCTAssertEqual(rows[1].bucket, week)
    }

    func testRowsShowUnavailableGeminiWhenConfiguredWithoutFreshCache() {
        let rows = UsageTextRow.rows(codex: nil, claude: nil, antigravity: .unavailable)
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Gemini W", "Codex W"])
        XCTAssertNil(rows[1].bucket)
        XCTAssertEqual(rows[1].kind, .gemini)
    }

    func testRowsAddOpenCodeGo() {
        let go = OpenCodeGoUsageSnapshot(rolling: week, weekly: week, monthly: nil, observedAt: observed)
        let rows = UsageTextRow.rows(codex: nil, claude: nil, openCodeGo: .snapshot(go))
        XCTAssertEqual(rows.map(\.label), ["Claude W", "Codex W", "Go W"])
        XCTAssertEqual(rows[2].bucket, week)
        XCTAssertEqual(UsageTextRow.rows(codex: nil, claude: nil, openCodeGo: .unavailable).map(\.label), ["Claude W", "Codex W", "Go W"])
    }

    func testPlainLineShowsRemainingPaceAndPercent() {
        // 残り40%、目安50%（残り時間が半分）: 0〜40% が塗られ、40〜50% が使いすぎ、50% に │。
        let row = UsageTextRow(label: "Claude W", bucket: week, observedAt: observed, kind: .claude)
        let line = UsageTextRenderer.line(for: row, width: 24, labelWidth: 9, color: false)
        XCTAssertEqual(line, "Claude W █████│····  40%")
        let colored = UsageTextRenderer.line(for: row, width: 24, labelWidth: 9, color: true)
        XCTAssertTrue(colored.contains("\u{1B}[38;2;247;118;142m"))
        XCTAssertTrue(colored.contains("\u{1B}[38;2;224;160;139m"))
        XCTAssertTrue(colored.contains("\u{1B}[38;2;104;114;148m"))
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

    func testAntigravityParserReadsGeminiWeeklyAndFiveHourOnly() throws {
        let body = """
        {
          "observed_at": 1780000000,
          "quota": {
            "gemini-5h": {
              "remaining_fraction": 0.75,
              "reset_in_seconds": 9000
            },
            "gemini-weekly": {
              "remaining_fraction": 0.9378,
              "reset_time": "2026-07-06T07:50:32Z",
              "reset_in_seconds": 560580
            },
            "3p-weekly": {
              "remaining_fraction": 0.10,
              "reset_in_seconds": 1000
            },
            "argon-5h": {
              "remaining_fraction": 0.20,
              "reset_in_seconds": 1000
            }
          }
        }
        """
        let snapshot = try XCTUnwrap(AntigravityUsageParser.snapshot(from: Data(body.utf8), observedAt: observed))
        XCTAssertEqual(snapshot.observedAt, Date(timeIntervalSince1970: 1_780_000_000))
        let weekly = try XCTUnwrap(snapshot.weekly)
        XCTAssertEqual(weekly.label, "W")
        XCTAssertEqual(weekly.remainingPercent, 93.78, accuracy: 0.001)
        XCTAssertEqual(weekly.windowSeconds, 7 * 24 * 60 * 60)
        XCTAssertEqual(weekly.resetAt, 1_783_324_232)

        let fiveHour = try XCTUnwrap(snapshot.fiveHour)
        XCTAssertEqual(fiveHour.label, "5h")
        XCTAssertEqual(fiveHour.remainingPercent, 75, accuracy: 0.001)
        XCTAssertEqual(fiveHour.windowSeconds, 5 * 60 * 60)
        XCTAssertEqual(fiveHour.resetAt, 1_780_009_000)
        XCTAssertEqual(try XCTUnwrap(fiveHour.paceRemainingPercent(at: snapshot.observedAt)), 50, accuracy: 0.001)
    }

    func testAntigravityParserIgnoresDisabledAndNonGeminiBuckets() {
        let body = """
        {
          "quota": {
            "gemini-weekly": {"remaining_fraction": 0.5, "disabled": true},
            "3p-weekly": {"remaining_fraction": 0.5}
          }
        }
        """
        XCTAssertNil(AntigravityUsageParser.snapshot(from: Data(body.utf8), observedAt: observed))
    }

    func testAntigravityReaderStates() throws {
        let missing = AntigravityUsageReader(
            configDirectory: URL(fileURLWithPath: "/nonexistent/antigravity-cli"),
            environment: [:]
        )
        XCTAssertEqual(missing.read(now: observed), .notConfigured)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configuredNoCache = AntigravityUsageReader(configDirectory: tempDir, environment: [:])
        XCTAssertEqual(configuredNoCache.read(now: observed), .unavailable)

        let cacheURL = tempDir.appendingPathComponent("cache/statusline-quota.json")
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date()
        let freshPayload = """
        {"observed_at": \(Int(now.timeIntervalSince1970)), "quota": {"gemini-weekly": {"remaining_fraction": 0.8, "reset_in_seconds": 302400}}}
        """
        try Data(freshPayload.utf8).write(to: cacheURL)
        let freshReader = AntigravityUsageReader(configDirectory: tempDir, environment: [:])
        if case let .snapshot(snapshot) = freshReader.read(now: now) {
            XCTAssertEqual(snapshot.weekly?.remainingPercent ?? -1, 80, accuracy: 0.001)
        } else {
            XCTFail("Expected fresh snapshot")
        }

        XCTAssertEqual(
            freshReader.read(now: now.addingTimeInterval(AntigravityUsageReader.maxCacheAge + 1)),
            .unavailable
        )
    }
}
