import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
#endif

// What the pull request popup shows: open PRs, plus merged or closed
// ones with an unread notification. The bar decodes this from
// omacchiato-github-prs; the previews build it by hand.
public struct PRReport {
    public enum State: String { case open, merged, closed }
    public enum Checks: String { case passed, failed, running }
    public enum Review: String { case approved, changes }

    // What a PR waits for, in the order the panel lists them.
    public enum Stage: Int, CaseIterable, Comparable {
        case needsYou, running, inReview, ready, draft, done

        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

        public var title: String {
            switch self {
            case .needsYou: return "Needs You"
            case .running: return "Checks Running"
            case .inReview: return "In Review"
            case .ready: return "Ready to Merge"
            case .draft: return "Drafts"
            case .done: return "Done"
            }
        }

        public var symbol: String {
            switch self {
            case .needsYou: return "exclamationmark.circle.fill"
            case .running: return "clock.fill"
            case .inReview: return "eye.circle.fill"
            case .ready: return "checkmark.circle.fill"
            case .draft: return "pencil.circle.fill"
            case .done: return "archivebox.circle.fill"
            }
        }

        public var tint: Color {
            switch self {
            case .needsYou: return PanelColors.red
            case .running: return PanelColors.orange
            case .inReview: return .blue
            case .ready: return PanelColors.green
            case .draft: return .gray
            case .done: return .purple
            }
        }
    }

    public struct PR: Identifiable {
        public var repo: String
        public var number: Int
        public var title: String
        public var url: URL?
        public var state: State
        public var draft: Bool
        public var checks: Checks?
        public var checkCounts: [Checks: Int]
        public var conflicts: Bool
        public var review: Review?
        public var threads: Int              // unresolved threads that someone else started
        public var unread: Bool
        public var depth: Int                // how many PRs of the stack it sits on
        public var additions: Int
        public var deletions: Int
        public var updated: Date?
        public var id: String { "\(repo)#\(number)" }

        public init(repo: String, number: Int, title: String, url: URL? = nil, state: State = .open,
                    draft: Bool = false, checks: Checks? = nil, checkCounts: [Checks: Int] = [:],
                    conflicts: Bool = false, review: Review? = nil, threads: Int = 0, unread: Bool = false,
                    depth: Int = 0, additions: Int = 0, deletions: Int = 0, updated: Date? = nil) {
            self.repo = repo
            self.number = number
            self.title = title
            self.url = url
            self.state = state
            self.draft = draft
            self.checks = checks
            self.checkCounts = checkCounts
            self.conflicts = conflicts
            self.review = review
            self.threads = threads
            self.unread = unread
            self.depth = depth
            self.additions = additions
            self.deletions = deletions
            self.updated = updated
        }

        public var stage: Stage {
            if state != .open { return .done }
            if draft { return .draft }
            if checks == .failed || conflicts || review == .changes || threads > 0 { return .needsYou }
            if checks == .running { return .running }
            return review == .approved ? .ready : .inReview
        }

        // Only what the stage does not already say.
        public var note: String? {
            switch state {
            case .merged: return "Merged"
            case .closed: return "Closed without merging"
            case .open: break
            }
            var parts: [String] = []
            if conflicts { parts.append("Merge conflicts") }
            if checks == .failed {
                let failed = checkCounts[.failed] ?? 0
                parts.append(failed > 0 ? "\(failed) check\(failed == 1 ? "" : "s") failed" : "Checks failed")
            }
            if review == .changes { parts.append("Changes requested") }
            if threads > 0 { parts.append("\(threads) thread\(threads == 1 ? "" : "s") to resolve") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        // Keep in sync with icon() in bin/omacchiato-github-prs.
        public var symbol: String {
            switch state {
            case .merged: return "arrow.triangle.merge"
            case .closed: return "xmark.circle.fill"
            case .open: break
            }
            if draft { return "pencil" }
            if checks == .failed || conflicts { return "exclamationmark.triangle.fill" }
            if checks == .running { return "clock.fill" }
            if review == .changes || threads > 0 { return "bubble.left.fill" }
            return review == .approved ? "checkmark.circle.fill" : "clock"
        }
    }

    public var now: Date
    public var prs: [PR]                    // by repo, each stack base first
    public var problem: String?             // why the list is old, when GitHub is out of reach
    public var updated: Date?               // when the list was read

    public init(now: Date, prs: [PR], problem: String? = nil, updated: Date? = nil) {
        self.now = now
        self.prs = prs
        self.problem = problem
        self.updated = updated
    }

    // The script caches a read for 5 minutes and the bar polls every 2, so a
    // normal read is under 7 minutes old. 15 minutes flags a stuck fetch.
    public static let staleAfter: TimeInterval = 15 * 60

    // When to show "Updated …" at the panel's foot: StaleNote already gives
    // the age once the read failed, so this stamp shows only when it did not.
    public var updatedStamp: Date? { problem == nil ? updated : nil }

    public func count(_ stage: Stage) -> Int { prs.filter { $0.stage == stage }.count }

    // The repositories with the most PRs first, then by name.
    public var repos: [(name: String, prs: [PR])] {
        var order: [String] = []
        var groups: [String: [PR]] = [:]
        for pr in prs {
            if groups[pr.repo] == nil { order.append(pr.repo) }
            groups[pr.repo, default: []].append(pr)
        }
        return order.map { ($0, groups[$0] ?? []) }
            .sorted { $0.prs.count != $1.prs.count ? $0.prs.count > $1.prs.count
                                                    : $0.name.lowercased() < $1.name.lowercased() }
    }
}

public struct PRActions {
    public var open: (URL) -> Void = { _ in }
    public var openAll: () -> Void = {}
    // Reads the data again, from a click on the "Updated" stamp. nil keeps the stamp plain.
    public var refresh: (() -> Void)?

    public init() {}
}

// 3 days reads as 3d, 5 hours as 5h, 12 minutes as 12m.
public func ageText(_ date: Date?, now: Date) -> String {
    guard let date else { return "" }
    let s = max(0, now.timeIntervalSince(date))
    if s < 3600 { return "\(Int(s / 60))m" }
    if s < 86400 { return "\(Int(s / 3600))h" }
    if s < 86400 * 30 { return "\(Int(s / 86400))d" }
    return "\(Int(s / (86400 * 30)))mo"
}

// The "panel" object that omacchiato-github-prs prints. Keep in sync with
// panel_pr() in bin/omacchiato-github-prs.
extension PRReport {
    public init?(json: [String: Any], now: Date = Date()) {
        guard json["kind"] as? String == "github-prs" else { return nil }
        let stamp = ISO8601DateFormatter()
        let prs = (json["prs"] as? [[String: Any]] ?? []).map { p in
            PR(repo: p["repo"] as? String ?? "", number: p["number"] as? Int ?? 0,
               title: p["title"] as? String ?? "", url: (p["url"] as? String).flatMap(URL.init(string:)),
               state: (p["state"] as? String).flatMap(State.init(rawValue:)) ?? .open,
               draft: p["draft"] as? Bool ?? false,
               checks: (p["checks"] as? String).flatMap(Checks.init(rawValue:)),
               checkCounts: Dictionary(uniqueKeysWithValues: (p["check_counts"] as? [String: Int] ?? [:])
                   .compactMap { k, v in Checks(rawValue: k).map { ($0, v) } }),
               conflicts: p["conflicts"] as? Bool ?? false,
               review: (p["review"] as? String).flatMap(Review.init(rawValue:)),
               threads: p["threads"] as? Int ?? 0, unread: p["unread"] as? Bool ?? false,
               depth: p["depth"] as? Int ?? 0, additions: p["additions"] as? Int ?? 0,
               deletions: p["deletions"] as? Int ?? 0,
               updated: (p["updated"] as? String).flatMap(stamp.date(from:)))
        }
        self.init(now: now, prs: prs, problem: json["problem"] as? String,
                  updated: (json["updated"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
    }
}
