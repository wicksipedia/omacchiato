import SwiftUI

// What the updates popup shows: the release the clone would move to, and
// the commits it does not have yet. The bar decodes this from
// omacchiato-updates; the previews build it by hand.
public struct UpdatesReport {
    public struct Commit: Identifiable, Equatable {
        public var hash: String
        public var subject: String
        public var age: String
        public var id: String { hash }

        public init(hash: String, subject: String, age: String) {
            self.hash = hash
            self.subject = subject
            self.age = age
        }
    }

    public var target: String?      // the release tag it would move to, or nil between releases
    public var commits: [Commit]
    public var more: Int            // commits beyond the ones shown
    public var update: String       // the omacchiato-update command for "Update Now"
    public var updated: Date?       // when the clone last fetched successfully
    public var channel: String      // "release" or "edge", as omacchiato-update --edge
    public var counts: [String: Int] // new commits on each channel; empty hides the choice

    public init(target: String? = nil, commits: [Commit] = [], more: Int = 0, update: String = "",
                updated: Date? = nil, channel: String = "release", counts: [String: Int] = [:]) {
        self.target = target
        self.commits = commits
        self.more = more
        self.update = update
        self.updated = updated
        self.channel = channel
        self.counts = counts
    }

    public var total: Int { commits.count + more }
}

public struct UpdatesActions {
    public var update: (String) -> Void = { _ in }
    public var setChannel: (String) -> Void = { _ in }
    // Reads the data again, from a click on the "Updated" stamp. nil keeps the stamp plain.
    public var refresh: (() -> Void)?

    public init() {}
}

// The "panel" object that omacchiato-updates prints. Keep in sync with
// panel_updates() in bin/omacchiato-updates.
extension UpdatesReport {
    public init?(json: [String: Any]) {
        guard json["kind"] as? String == "updates" else { return nil }
        let commits = (json["commits"] as? [[String: Any]] ?? []).map {
            Commit(hash: $0["hash"] as? String ?? "", subject: $0["subject"] as? String ?? "",
                  age: $0["age"] as? String ?? "")
        }
        self.init(target: json["target"] as? String, commits: commits, more: json["more"] as? Int ?? 0,
                  update: json["update"] as? String ?? "",
                  updated: (json["updated"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
                  channel: json["channel"] as? String ?? "release", counts: json["counts"] as? [String: Int] ?? [:])
    }
}
