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
