import Foundation

nonisolated enum FanControlServiceConstants {
  static let machServiceName = "com.mishkacher.MacVitals.FanControl"
  static let daemonPlistName = "com.mishkacher.MacVitals.FanControl.plist"
  static let helperExecutableName = "MacVitalsFanHelper"
}

@objc protocol FanControlXPCProtocol {
  func status(reply: @escaping (Bool, String?) -> Void)
  func setFanBoost(
    index: Int,
    requestedRPM: Double,
    leaseSeconds: Double,
    reply: @escaping (Bool, Double, String?) -> Void)
  func setFanAutomatic(index: Int, reply: @escaping (Bool, String?) -> Void)
  func setAllFansAutomatic(reply: @escaping (Bool, String?) -> Void)
}
