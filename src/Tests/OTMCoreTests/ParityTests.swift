import Foundation
import Testing
@testable import OTMCore

/// Swift ↔ JS scoring parity (phone/test/mapper.test.js reads the same two fixtures).
/// Regenerate the expected file after an intentional change: `UPDATE_PARITY=1 swift test --filter ParityTests`.
@Suite struct ParityTests {
    struct Case: Decodable { var name: String; var axes: AxesConfig; var issues: [JiraIssue] }
    struct Input: Decodable { var today: String; var site: String; var cases: [Case] }
    struct Out: Codable, Equatable { var name: String; var tasks: [RenderTask] }

    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fixtures")

    @Test func matchesExpected() throws {
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: Self.dir.appendingPathComponent("parity-input.json")))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let p = input.today.split(separator: "-").compactMap { Int($0) }
        let now = utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
        let site = URL(string: input.site)!
        let out = input.cases.map { c -> Out in
            let tasks = AxisMapper.map(issues: c.issues, axes: c.axes, site: site, now: now, calendar: utc)
            let rendered = Scorer.rank(tasks).map { s -> RenderTask in
                let t = s.task
                return RenderTask(key: t.key, summary: t.summary, status: t.status, priority: t.priority, due: t.due,
                                  url: t.url, value: t.value, effort: t.effort, urgency: t.urgency, missing: t.missing,
                                  derived: t.derived, score: s.score, rank: s.rank, fire: s.fire, changed: false)
            }
            return Out(name: c.name, tasks: rendered)
        }
        let path = Self.dir.appendingPathComponent("parity-expected.json")
        if ProcessInfo.processInfo.environment["UPDATE_PARITY"] == "1" {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try e.encode(out).write(to: path)
        }
        let expected = try JSONDecoder().decode([Out].self, from: Data(contentsOf: path))
        #expect(out == expected)
    }
}
