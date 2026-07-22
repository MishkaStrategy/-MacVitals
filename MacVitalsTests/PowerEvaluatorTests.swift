import XCTest
@testable import MacVitals

final class PowerEvaluatorTests: XCTestCase {
    func testSustainedBatteryDischargeIsInsufficient() {
        var evaluator = ChargerSufficiencyEvaluator(configuration: .init(insufficientDischargeWatts: 2, borderlineDischargeWatts: 0.5, confirmationDuration: 20, minimumSamples: 5, maximumTimestampSkew: 5))
        let start = Date()
        var result: PowerAssessment?
        for index in 0..<6 {
            result = evaluator.evaluate(.init(timestamp: start.addingTimeInterval(Double(index) * 4), externalPower: true,
                                              batteryPowerWatts: -4, adapterRatedPowerWatts: 30,
                                              adapterMeasuredPowerWatts: nil, batteryPercent: 60))
        }
        XCTAssertEqual(result?.status, .insufficient)
    }
    func testChargingBatteryIsNotInsufficient() {
        var evaluator = ChargerSufficiencyEvaluator(configuration: .init(insufficientDischargeWatts: 2, borderlineDischargeWatts: 0.5, confirmationDuration: 20, minimumSamples: 3, maximumTimestampSkew: 5))
        let start = Date()
        var result: PowerAssessment?
        for index in 0..<4 { result = evaluator.evaluate(.init(timestamp: start.addingTimeInterval(Double(index) * 5), externalPower: true, batteryPowerWatts: 5, adapterRatedPowerWatts: 67, adapterMeasuredPowerWatts: nil, batteryPercent: 50)) }
        XCTAssertEqual(result?.status, .chargingBattery)
    }
    func testNoAdapterIsNotConnected() {
        var evaluator = ChargerSufficiencyEvaluator()
        let result = evaluator.evaluate(.init(timestamp: Date(), externalPower: false, batteryPowerWatts: -10, adapterRatedPowerWatts: nil, adapterMeasuredPowerWatts: nil, batteryPercent: 50))
        XCTAssertEqual(result.status, .notConnected)
    }
}
