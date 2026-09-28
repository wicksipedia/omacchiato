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

    public init(target: String? = nil, commits: [Commit] = [], more: Int = 0, update: String = "") {
        self.target = target
        self.commits = commits
        self.more = more
        self.update = update
    }

    public var total: Int { commits.count + more }
}

public struct UpdatesActions {
    public var update: (String) -> Void = { _ in }

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
                  update: json["update"] as? String ?? "")
    }
}
