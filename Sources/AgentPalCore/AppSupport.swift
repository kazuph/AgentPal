import Foundation

public enum AppSupport {
    public static let bundleIdentifier = "dev.agentpal"
    public static let appName = "agentpal"

    public static var supportDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/agentpal")
    }

    public static func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }
}
