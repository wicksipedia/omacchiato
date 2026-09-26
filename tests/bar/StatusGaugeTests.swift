import Testing
import StatusGauge

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

}
