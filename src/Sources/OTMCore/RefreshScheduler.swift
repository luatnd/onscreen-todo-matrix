import Foundation

public enum RefreshTrigger: Equatable, Sendable {
    case manual, focus, timer
}

/// Decides whether a refresh should run. The app owns the actual timer.
public final class RefreshScheduler {
    public static let focusMinInterval: TimeInterval = 30
    public static let defaultBackoff: TimeInterval = 60

    private let now: () -> Date
    public private(set) var lastFetch: Date?
    public private(set) var backoffUntil: Date?
    public private(set) var isPaused = false

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func shouldRefresh(_ trigger: RefreshTrigger, intervalMinutes: Int) -> Bool {
        let t = now()
        if let until = backoffUntil, t < until { return false }
        switch trigger {
        case .manual:
            return true
        case .focus:
            guard !isPaused else { return false }
            guard let last = lastFetch else { return true }
            return t.timeIntervalSince(last) > Self.focusMinInterval
        case .timer:
            guard !isPaused, intervalMinutes > 0 else { return false }
            guard let last = lastFetch else { return true }
            return t.timeIntervalSince(last) >= Double(intervalMinutes) * 60 - 1
        }
    }

    public func recordSuccess() {
        lastFetch = now()
        backoffUntil = nil
        isPaused = false
    }

    public func recordFailure(_ error: JiraError) {
        switch error {
        case .unauthorized: isPaused = true
        case .rateLimited(let retryAfter): backoffUntil = now().addingTimeInterval(retryAfter ?? Self.defaultBackoff)
        default: break
        }
    }

    /// Call after credentials or JQL change.
    public func resume() {
        isPaused = false
        backoffUntil = nil
    }
}
