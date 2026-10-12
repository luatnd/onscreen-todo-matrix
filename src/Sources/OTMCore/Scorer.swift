import Foundation

public struct ScoredTask: Equatable, Sendable {
    public var task: MappedTask
    public var score: Double
    public var rank: Int?
    public var fire: Bool
}

public enum Scorer {
    public static func score(value: Double, effort: Double, urgency: Double) -> Double {
        value * (0.5 + urgency) / (0.3 + effort)
    }

    public static func isFire(value: Double, urgency: Double) -> Bool {
        value >= 0.7 && urgency >= 0.8
    }

    /// Sorted by score (desc), then key (asc). The first three get rank 1…3.
    public static func rank(_ tasks: [MappedTask]) -> [ScoredTask] {
        tasks
            .map { ScoredTask(task: $0, score: score(value: $0.value, effort: $0.effort, urgency: $0.urgency),
                              rank: nil, fire: isFire(value: $0.value, urgency: $0.urgency)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.task.key < $1.task.key }
            .enumerated()
            .map { i, s in var s = s; s.rank = i < 3 ? i + 1 : nil; return s }
    }
}
