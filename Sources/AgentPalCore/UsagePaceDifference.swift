import Foundation

public struct UsagePaceDifference: Equatable {
    public enum Kind { case overuse, surplus }
    public let kind: Kind
    public let lower: Double
    public let upper: Double

    public static func between(remaining: Double, pace: Double?) -> UsagePaceDifference? {
        guard let pace else { return nil }
        let r = min(max(remaining, 0), 100)
        let p = min(max(pace, 0), 100)
        guard r != p else { return nil }
        return UsagePaceDifference(kind: r < p ? .overuse : .surplus, lower: min(r, p), upper: max(r, p))
    }
}
