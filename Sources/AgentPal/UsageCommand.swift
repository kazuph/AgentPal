import Foundation
import AgentPalCore

/// `agentpal usage [--width N] [--no-color]` prints the usage rows as text bars
/// (for ikesu's sidebar plugin) and exits without starting the menu bar app.
enum UsageCommand {
    private final class Box: @unchecked Sendable {
        var codex: CodexUsageSnapshot?
        var claude: ClaudeUsageSnapshot?
    }

    static func run(arguments: [String]) -> Never {
        let environment = ProcessInfo.processInfo.environment
        var width = Int(environment["IKESU_SIDEBAR_COLUMNS"] ?? "") ?? Int(environment["COLUMNS"] ?? "") ?? 26
        var color = environment["NO_COLOR"] == nil
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--width":
                guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
                    fputs("--width requires a positive number\n", stderr)
                    Foundation.exit(2)
                }
                width = value
                index += 1
            case "--no-color":
                color = false
            case "-h", "--help":
                print("usage: agentpal usage [--width N] [--no-color]")
                Foundation.exit(0)
            default:
                fputs("unknown option: \(arguments[index])\n", stderr)
                Foundation.exit(2)
            }
            index += 1
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.codex = await CodexUsageReader().readLatest()
            box.claude = await ClaudeUsageReader().readLatest()
            done.signal()
        }
        done.wait()
        let rows = UsageTextRow.rows(codex: box.codex, claude: box.claude)
        print(UsageTextRenderer.render(rows: rows, width: width, color: color))
        Foundation.exit(0)
    }
}
