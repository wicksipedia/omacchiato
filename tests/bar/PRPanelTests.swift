import Foundation
import Testing
@testable import PRPanel

@Suite struct PRPanelTests {
    typealias PR = PRReport.PR

    @Test("a PR waits for the first thing that stops it")
    func stages() {
        #expect(PR(repo: "a/b", number: 1, title: "", draft: true, checks: .failed).stage == .draft)
        #expect(PR(repo: "a/b", number: 1, title: "", checks: .running, threads: 1).stage == .needsYou)
        #expect(PR(repo: "a/b", number: 1, title: "", checks: .running, review: .approved).stage == .running)
        #expect(PR(repo: "a/b", number: 1, title: "", checks: .passed, review: .approved).stage == .ready)
        #expect(PR(repo: "a/b", number: 1, title: "", checks: .passed).stage == .inReview)
        #expect(PR(repo: "a/b", number: 1, title: "", state: .merged, checks: .failed).stage == .done)
        #expect(PR(repo: "a/b", number: 1, title: "", checks: .failed, checkCounts: [.failed: 2], threads: 1).note
                == "2 checks failed · 1 thread to resolve")
    }

    // The spec's example: #3 of five has a failed check, the rest wait for review.
    static let fiveStack = PRReport(now: Date(), prs: (1...5).map {
        PR(repo: "a/b", number: $0, title: "", checks: $0 == 3 ? .failed : .passed,
           checkCounts: $0 == 3 ? [.failed: 1] : [:], depth: $0 - 1)
    })

    @Test("a stacked PR takes the worst stage of the PRs below it")
    func rollUp() {
        let prs = Self.fiveStack.prs
        #expect(prs.map(\.stage) == [.inReview, .inReview, .needsYou, .needsYou, .needsYou])
        #expect(prs.map(\.blockedBy) == [nil, nil, nil, 3, 3])
        #expect(prs[2].note == "1 check failed")
        #expect(prs[3].note == "Waits on #3")
    }

    @Test("a ready PR waits on running checks below it, and a draft or merged PR blocks nothing")
    func rollUpEdges() {
        let running = PRReport(now: Date(), prs: [
            PR(repo: "a/b", number: 1, title: "", checks: .running),
            PR(repo: "a/b", number: 2, title: "", checks: .passed, review: .approved, depth: 1),
        ]).prs
        #expect(running[1].stage == .running)
        let draft = PRReport(now: Date(), prs: [
            PR(repo: "a/b", number: 1, title: "", draft: true),
            PR(repo: "a/b", number: 2, title: "", checks: .passed, review: .approved, depth: 1),
            PR(repo: "a/b", number: 3, title: "", draft: true, checks: .failed, depth: 2),
        ]).prs
        #expect(draft.map(\.stage) == [.draft, .ready, .draft])
        #expect(draft.map(\.blockedBy) == [nil, nil, nil])
    }

    @Test("each branch of a stack rolls up on its own, and a PR with no parent starts a chain")
    func rollUpBranches() {
        let prs = PRReport(now: Date(), prs: [
            PR(repo: "a/b", number: 1, title: "", checks: .passed),
            PR(repo: "a/b", number: 2, title: "", checks: .failed, depth: 1),
            PR(repo: "a/b", number: 3, title: "", checks: .passed, depth: 2),
            PR(repo: "a/b", number: 4, title: "", checks: .passed, depth: 1),
            PR(repo: "c/d", number: 5, title: "", checks: .passed, depth: 2),
        ]).prs
        #expect(prs.map(\.blockedBy) == [nil, nil, 2, nil, nil])
        #expect(prs[4].stage == .inReview)
    }

    @Test("the panel reads the script's JSON")
    func decode() throws {
        let text = """
        {"kind": "github-prs", "updated": 1790550885.9, "problem": "offline",
         "prs": [{"repo": "a/b", "number": 7, "title": "Fix it", "url": "https://github.com/a/b/pull/7",
                  "state": "open", "draft": false, "checks": "failed", "check_counts": {"failed": 2, "passed": 9},
                  "conflicts": false, "review": "changes", "threads": 0, "unread": true, "depth": 1,
                  "additions": 12, "deletions": 3, "updated": "2026-09-18T06:14:31Z"}]}
        """
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let report = try #require(PRReport(json: json))
        let pr = try #require(report.prs.first)
        #expect(pr.id == "a/b#7" && pr.checks == .failed && pr.review == .changes && pr.unread)
        #expect(pr.checkCounts == [.failed: 2, .passed: 9])
        #expect(pr.depth == 1 && pr.updated != nil)
        #expect(report.problem == "offline" && report.updated != nil)
        #expect(PRReport(json: ["kind": "ai-usage"]) == nil)
    }

    @Test("the updated stamp hides once StaleNote already gives the age")
    func updatedStamp() {
        let now = Date()
        #expect(PRReport(now: now, prs: [], updated: now).updatedStamp == now)
        #expect(PRReport(now: now, prs: [], problem: "offline", updated: now).updatedStamp == nil)
        #expect(PRReport(now: now, prs: []).updatedStamp == nil)
    }
}

@Test func longSwipeNeedsALaidOutRow() {
    #expect(SwipeToMarkRead.pastButton(offset: 200, content: 456, container: 380))
    #expect(!SwipeToMarkRead.pastButton(offset: 76, content: 456, container: 380))
    #expect(!SwipeToMarkRead.pastButton(offset: 0, content: 456, container: 0))
}
