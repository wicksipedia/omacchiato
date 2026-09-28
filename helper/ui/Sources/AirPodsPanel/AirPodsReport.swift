import AppKit
import SwiftUI

// What the AirPods popup shows: each connected AirPods Pro or Max, its
// batteries and its noise control. The bar decodes this from
// omacchiato-airpods; the previews build it by hand.
public struct AirPodsReport {
    public struct Mode: Identifiable, Equatable {
        public var id: String           // airpods-control's name: off, transparency, adaptive, noise-cancellation
        public var title: String
        public var run: String          // the command that sets it

        public init(id: String, title: String, run: String = "") {
            self.id = id
            self.title = title
            self.run = run
        }

        public var symbol: String {
            switch id {
            case "off": return "person.fill"
            case "transparency": return "person.and.background.dotted"
            case "adaptive": return "person.wave.2.fill"
            case "noise-cancellation": return "person.and.background.striped.horizontal"
            default: return "ear"
            }
        }
    }

    public struct Battery: Identifiable, Equatable {
        public var part: String         // Left, Right, Case, or Battery for AirPods Max
        public var percent: Int
        public var id: String { part }

        public init(part: String, percent: Int) {
            self.part = part
            self.percent = percent
        }

        public var low: Bool { percent <= 20 }
    }

    public struct Device: Identifiable {
        public var name: String
        public var model: String
        public var type: String         // the Uniform Type Identifier from CoreTypes, such as com.apple.airpods-pro-gen2
        public var batteries: [Battery]
        public var cable: Bool
        public var mode: String?
        public var modes: [Mode]
        public var id: String { name }

        public init(name: String, model: String, type: String, batteries: [Battery], cable: Bool = false,
                    mode: String? = nil, modes: [Mode] = []) {
            self.name = name
            self.model = model
            self.type = type
            self.batteries = batteries
            self.cable = cable
            self.mode = mode
            self.modes = modes
        }

        public var isMax: Bool { type.hasPrefix("com.apple.airpods-max") }

        // "Matt's AirPods Pro" over "AirPods Pro" says the same thing twice.
        public var subtitle: String? {
            let n = name.lowercased(), m = model.lowercased()
            return n.contains(m) || m.contains(n) ? nil : model
        }
    }

    public var devices: [Device]
    public var settings: URL?

    public init(devices: [Device], settings: URL? = nil) {
        self.devices = devices
        self.settings = settings
    }
}

public struct AirPodsActions {
    public var setMode: (AirPodsReport.Mode) -> Void = { _ in }
    public var openSettings: () -> Void = {}

    public init() {}
}

// The "panel" object that omacchiato-airpods prints. Keep in sync with
// panel_device() in bin/omacchiato-airpods.
extension AirPodsReport {
    static let batteryOrder = ["Left", "Right", "Battery", "Case"]

    public init?(json: [String: Any]) {
        guard json["kind"] as? String == "airpods" else { return nil }
        let devices = (json["devices"] as? [[String: Any]] ?? []).map { d in
            let batteries = (d["battery"] as? [String: Int] ?? [:])
                .map { Battery(part: $0.key, percent: $0.value) }
                .sorted { (Self.batteryOrder.firstIndex(of: $0.part) ?? 9, $0.part)
                    < (Self.batteryOrder.firstIndex(of: $1.part) ?? 9, $1.part) }
            let modes = (d["modes"] as? [[String: Any]] ?? []).map {
                Mode(id: $0["id"] as? String ?? "", title: $0["title"] as? String ?? "", run: $0["run"] as? String ?? "")
            }
            return Device(name: d["name"] as? String ?? "", model: d["model"] as? String ?? "",
                          type: d["type"] as? String ?? "", batteries: batteries, cable: d["cable"] as? Bool ?? false,
                          mode: d["mode"] as? String, modes: modes)
        }
        self.init(devices: devices, settings: (json["settings"] as? String).flatMap(URL.init(string:)))
    }
}

// Apple's own product renders, from the frameworks behind the AirPods
// pages of System Settings. The frameworks are private, so a name can
// change in a macOS update. Then the panel draws an SF Symbol instead.
enum ProductArt {
    private static var cache: [String: [NSImage]] = [:]

    // The pictures of one product, left to right.
    static func images(for type: String) -> [NSImage] {
        if let hit = cache[type] { return hit }
        let found: [NSImage]
        if type.hasPrefix("com.apple.airpods-max") {
            found = load("HeadphoneAssets", ["B515d-Default"])
        } else if type == "com.apple.airpods-pro-2025" {
            found = load("HeadphoneSettingsUI", ["B788_airpod_left", "B788_airpod_right"])
        } else if type.hasPrefix("com.apple.airpods-pro") {
            found = load("HeadphoneAssets", ["airpod_left", "airpod_right"])
        } else {
            found = []
        }
        cache[type] = found
        return found
    }

    private static func load(_ framework: String, _ names: [String]) -> [NSImage] {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/\(framework).framework") else { return [] }
        let images = names.compactMap { bundle.image(forResource: $0) }
        return images.count == names.count ? images : []
    }
}
