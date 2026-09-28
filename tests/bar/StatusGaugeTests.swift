import Testing
@testable import StatusGauge
@testable import StatusPanel

@Suite struct StatusGaugeTests {
    @Test("the battery ring is red at 20 % or less, unless it charges")
    func low() {
        #expect(StatusGauge(battery: 0.2).batteryLow)
        #expect(!StatusGauge(battery: 0.21).batteryLow)
        #expect(!StatusGauge(battery: 0.1, charging: true).batteryLow)
    }

    @Test("the ring fills clockwise from its lower-left end")
    func ring() {
        #expect(StatusGauge(battery: 0).ringEnd == 220)
        #expect(StatusGauge(battery: 1).ringEnd == -40)
        #expect(StatusGauge(battery: 2).ringEnd == -40)
    }

    @Test("signal strength lights one to four dots")
    func wifi() {
        #expect(wifiLevel(rssi: 0) == 0)
        #expect(wifiLevel(rssi: -50) == 4)
        #expect(wifiLevel(rssi: -60) == 3)
        #expect(wifiLevel(rssi: -70) == 2)
        #expect(wifiLevel(rssi: -85) == 1)
    }

    @Test("a cable shows the Ethernet mark with every dot lit, and a phone's hotspot the chain link")
    func link() {
        let wifi = StatusReport.WiFi(ssid: "Home", ip: "192.168.1.2", router: "192.168.1.1", rssi: -70)
        #expect(StatusReport(battery: nil, wifi: wifi).gauge.link == .wifi)

        let wired = StatusReport(battery: nil, wifi: StatusReport.WiFi(), ethernet: .init(name: "LAN", ip: "10.0.0.2"))
        #expect(wired.gauge.link == .ethernet)
        #expect(wired.gauge.dots == 4)

        var phone = wifi
        phone.router = "172.20.10.1"
        #expect(StatusReport(battery: nil, wifi: phone).gauge.link == .hotspot)
        #expect(StatusReport(battery: nil, wifi: phone).gauge.dots == 2)
        phone.router = nil
        phone.phones = [.init(name: "Home", connected: true)]
        #expect(StatusReport(battery: nil, wifi: phone).gauge.link == .hotspot)
    }
}
