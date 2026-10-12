import Foundation
import Testing
@testable import OTMCore

private func task(_ key: String, v: Double, e: Double, u: Double) -> MappedTask {
    MappedTask(key: key, summary: key, status: "", priority: nil, due: nil, url: "u/\(key)", value: v, effort: e, urgency: u)
}

@Suite struct ScorerTests {
    @Test func formulaMatchesSpec() {
        #expect(abs(Scorer.score(value: 0.95, effort: 0.1, urgency: 1) - 3.5625) < 1e-9)
        #expect(Scorer.score(value: 0, effort: 0, urgency: 1) == 0)
    }

    @Test func fireThresholdsAreInclusive() {
        #expect(Scorer.isFire(value: 0.7, urgency: 0.8))
        #expect(!Scorer.isFire(value: 0.69, urgency: 1))
        #expect(!Scorer.isFire(value: 1, urgency: 0.79))
    }

    @Test func ranksTopThreeByScoreThenKey() {
        let scored = Scorer.rank([
            task("D", v: 0.1, e: 0.9, u: 0.1), task("B", v: 1, e: 0, u: 1),
            task("A", v: 1, e: 0, u: 1), task("C", v: 0.9, e: 0.2, u: 0.5),
        ])
        #expect(scored.map(\.task.key) == ["A", "B", "C", "D"])
        #expect(scored.map(\.rank) == [1, 2, 3, nil])
    }

    @Test func emptyInput() {
        #expect(Scorer.rank([]).isEmpty)
    }
}

@Suite struct RenderStateTests {
    @Test func buildMarksChangedOnlyAgainstPrevious() {
        let old = task("A", v: 0.5, e: 0.5, u: 0.5)
        let moved = task("A", v: 0.9, e: 0.5, u: 0.5)
        let same = task("B", v: 0.2, e: 0.2, u: 0.2)
        let new = task("C", v: 0.3, e: 0.3, u: 0.3)
        let s = RenderStateBuilder.build(tasks: [moved, same, new], previous: ["A": old, "B": same],
                                         config: AppConfig(), status: RenderStatus(), configured: true)
        let changed = Dictionary(uniqueKeysWithValues: s.tasks.map { ($0.key, $0.changed) })
        #expect(changed == ["A": true, "B": false, "C": false])
        let noDiff = RenderStateBuilder.build(tasks: [moved], previous: nil, config: AppConfig(),
                                              status: RenderStatus(), configured: true)
        #expect(noDiff.tasks[0].changed == false)
    }

    @Test func buildCopiesConfigAndScores() {
        var c = AppConfig()
        c.quick.labelMode = "key"
        c.presets.append(JQLPreset(id: "p2", name: "Team", jql: "project = X"))
        let s = RenderStateBuilder.build(tasks: [task("A", v: 1, e: 0, u: 1)], previous: nil, config: c,
                                         status: RenderStatus(syncedAt: nil, banner: "b", truncated: nil), configured: false)
        #expect(s.settings.labelMode == "key")
        #expect(s.presets == [RenderPreset(id: "my-open-work", name: "My open work"), RenderPreset(id: "p2", name: "Team")])
        #expect(s.activePresetId == "my-open-work")
        #expect(s.tasks[0].rank == 1)
        #expect(s.tasks[0].fire)
        #expect(s.status.banner == "b")
        #expect(!s.configured)
    }

    @Test func sharedFixtureDecodesAndRoundTrips() throws {
        // Contract test: the same file is decoded by chart/test/state.test.js.
        let data = try Data(contentsOf: srcDirectory.appendingPathComponent("fixtures/render-state.json"))
        let state = try RenderStateBuilder.decoder().decode(RenderState.self, from: data)
        #expect(state.tasks.count == 3)
        #expect(state.tasks[2].missing.effort)
        #expect(state.tasks[2].rank == nil)
        #expect(state.view == ViewDefaults())
        #expect(state.settings == QuickSettings())
        let again = try RenderStateBuilder.decoder().decode(RenderState.self, from: RenderStateBuilder.encoder().encode(state))
        #expect(again == state)
    }

    @Test func encodesSpecialCharactersSafely() throws {
        var t = task("Q-1", v: 0.5, e: 0.5, u: 0.5)
        t.summary = "Quote \" backslash \\ </script> emoji 🔥 line\u{2028}sep"
        let s = RenderStateBuilder.build(tasks: [t], previous: nil, config: AppConfig(), status: RenderStatus(), configured: true)
        let back = try RenderStateBuilder.decoder().decode(RenderState.self, from: RenderStateBuilder.encoder().encode(s))
        #expect(back.tasks[0].summary == t.summary)
    }
}
