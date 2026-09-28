import Foundation

// What the status popup shows. The bar reads it from IOKit and CoreWLAN,
// and the previews build it by hand.
public struct StatusReport: Equatable {
    public struct Battery: Equatable {
        public var percent: Int
        public var charging: Bool
        public var onAC: Bool
        public var minutesLeft: Int?     // to empty, or to full on AC
        public var mode: String?         // "low power" or "high power"
        public var thermal: String?      // only above nominal
        public var watts: Double?
        public var adapterWatts: Int?
        public var health: Int?
        public var cycles: Int?

        public init(percent: Int, charging: Bool = false, onAC: Bool = false, minutesLeft: Int? = nil,
                    mode: String? = nil, thermal: String? = nil, watts: Double? = nil,
                    adapterWatts: Int? = nil, health: Int? = nil, cycles: Int? = nil) {
            self.percent = percent
            self.charging = charging
            self.onAC = onAC
            self.minutesLeft = minutesLeft
            self.mode = mode
            self.thermal = thermal
            self.watts = watts
            self.adapterWatts = adapterWatts
            self.health = health
            self.cycles = cycles
        }

        public var low: Bool { percent <= 20 && !onAC }

        public var state: String {
            charging ? "Charging" : (onAC ? "Charged" : "On battery")
        }

        public var timeText: String? {
            guard let m = minutesLeft, m > 0 else { return nil }
            let time = m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
            return time + (onAC ? " to full" : " left")
        }
    }

    public struct Network: Equatable, Identifiable {
        public var ssid: String
        public var rssi: Int
        public var open: Bool
        public var id: String { ssid }

        public init(ssid: String, rssi: Int, open: Bool = false) {
            self.ssid = ssid
            self.rssi = rssi
            self.open = open
        }
    }

    public struct Phone: Equatable, Identifiable {
        public var name: String
        public var battery: Int?
        public var connected: Bool
        public var id: String { name }

        public init(name: String, battery: Int? = nil, connected: Bool = false) {
            self.name = name
            self.battery = battery
            self.connected = connected
        }
    }

    public struct WiFi: Equatable {
        public var on: Bool
        public var ssid: String?
        public var ip: String?
        public var router: String?
        public var rssi: Int?
        public var rate: Int?
        public var security: String?
        public var channel: Int?
        public var band: String?
        public var width: String?
        public var networks: [Network]
        public var scanning: Bool
        public var phones: [Phone]

        public init(on: Bool = true, ssid: String? = nil, ip: String? = nil, router: String? = nil,
                    rssi: Int? = nil, rate: Int? = nil, security: String? = nil, channel: Int? = nil,
                    band: String? = nil, width: String? = nil, networks: [Network] = [],
                    scanning: Bool = false, phones: [Phone] = []) {
            self.on = on
            self.ssid = ssid
            self.ip = ip
            self.router = router
            self.rssi = rssi
            self.rate = rate
            self.security = security
            self.channel = channel
            self.band = band
            self.width = width
            self.networks = networks
            self.scanning = scanning
            self.phones = phones
        }

        // An iPhone hotspot gives out 172.20.10.x and takes the phone's name.
        public var hotspot: Bool {
            router == "172.20.10.1" || phones.contains(where: \.connected)
        }

        public var verdict: String? {
            rssi.map { $0 >= -55 ? "Excellent" : ($0 >= -67 ? "Good" : ($0 >= -75 ? "Fair" : "Weak")) }
        }
    }

    public struct Ethernet: Equatable {
        public var name: String          // the adapter, such as "USB 10/100/1000 LAN"
        public var ip: String
        public var router: String?

        public init(name: String, ip: String, router: String? = nil) {
            self.name = name
            self.ip = ip
            self.router = router
        }
    }

    public var battery: Battery?        // nil on a Mac with no battery
    public var wifi: WiFi
    public var ethernet: Ethernet?      // set while the Mac's traffic goes over a cable

    public init(battery: Battery?, wifi: WiFi, ethernet: Ethernet? = nil) {
        self.battery = battery
        self.wifi = wifi
        self.ethernet = ethernet
    }
}

// The buttons in the panel call back into the bar.
public struct StatusActions {
    public var join: (String) -> Void = { _ in }
    public var hotspot: (String) -> Void = { _ in }
    public var toggleWifi: () -> Void = {}
    public var batterySettings: () -> Void = {}
    public var networkSettings: () -> Void = {}

    public init() {}
}

// Signal strength as the fill of the wi-fi symbol.
func signalFill(_ rssi: Int) -> Double {
    if rssi >= -60 { return 1 }
    if rssi >= -70 { return 0.66 }
    if rssi >= -80 { return 0.33 }
    return 0.1
}
