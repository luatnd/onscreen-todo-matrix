import Foundation
import Testing
@testable import OTMCore

final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

@Suite struct RefreshSchedulerTests {
    let clock = FakeClock()
    var s: RefreshScheduler { RefreshScheduler(now: { [clock] in clock.now }) }

    @Test func firstFetchAlwaysAllowed() {
        let s = self.s
        #expect(s.shouldRefresh(.focus, intervalMinutes: 5))
        #expect(s.shouldRefresh(.timer, intervalMinutes: 5))
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
    }

    @Test func focusNeedsMoreThan30Seconds() {
        let s = self.s
        s.recordSuccess()
        clock.advance(30)
        #expect(!s.shouldRefresh(.focus, intervalMinutes: 5))
        clock.advance(1)
        #expect(s.shouldRefresh(.focus, intervalMinutes: 5))
    }

    @Test func timerFollowsIntervalAndOff() {
        let s = self.s
        s.recordSuccess()
        clock.advance(4 * 60)
        #expect(!s.shouldRefresh(.timer, intervalMinutes: 5))
        clock.advance(60)
        #expect(s.shouldRefresh(.timer, intervalMinutes: 5))
        #expect(!s.shouldRefresh(.timer, intervalMinutes: 0))
    }

    @Test func unauthorizedPausesAutomaticTriggersButNotManual() {
        let s = self.s
        s.recordFailure(.unauthorized)
        clock.advance(3600)
        #expect(s.isPaused)
        #expect(!s.shouldRefresh(.focus, intervalMinutes: 5))
        #expect(!s.shouldRefresh(.timer, intervalMinutes: 5))
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
        s.resume()
        #expect(s.shouldRefresh(.timer, intervalMinutes: 5))
    }

    @Test func rateLimitBacksOffForRetryAfter() {
        let s = self.s
        s.recordFailure(.rateLimited(retryAfter: 12))
        clock.advance(11)
        #expect(!s.shouldRefresh(.manual, intervalMinutes: 5))
        clock.advance(2)
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
    }

    @Test func rateLimitWithoutHeaderBacksOff60s() {
        // Review Focus #5
        let s = self.s
        s.recordFailure(.rateLimited(retryAfter: nil))
        clock.advance(59)
        #expect(!s.shouldRefresh(.manual, intervalMinutes: 5))
        clock.advance(2)
        #expect(s.shouldRefresh(.manual, intervalMinutes: 5))
    }

    @Test func successClearsPauseAndBackoff() {
        let s = self.s
        s.recordFailure(.unauthorized)
        s.recordFailure(.rateLimited(retryAfter: 100))
        s.recordSuccess()
        #expect(!s.isPaused)
        #expect(s.backoffUntil == nil)
        #expect(s.lastFetch == clock.now)
    }

    @Test func networkErrorsDoNotPause() {
        let s = self.s
        s.recordFailure(.network("offline"))
        #expect(!s.isPaused)
        #expect(s.shouldRefresh(.focus, intervalMinutes: 5))
    }
}
