import XCTest
@testable import MacVitals

@MainActor
final class StatusBarPetSettingsStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "StatusBarPetSettingsStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testRuntimeSmokeModeEnablesDetailedModelWithoutPersistingOverride() throws {
    var persisted = StatusBarPetConfiguration.electricDragon
    persisted.isEnabled = false
    persisted.size = .tiny
    defaults.set(
      try XCTUnwrap(StatusBarPetConfigurationPersistence.encode(persisted)),
      forKey: StatusBarPetSettingsStore.defaultsKey)

    let store = StatusBarPetSettingsStore(
      defaults: defaults,
      runtimeSmokeEnabled: true)

    XCTAssertTrue(store.configuration.isEnabled)
    XCTAssertTrue(store.configuration.roamEnabled)
    XCTAssertFalse(store.configuration.cursorInteractionEnabled)
    XCTAssertFalse(store.configuration.respectReducedMotion)
    XCTAssertEqual(store.configuration.size, .medium)
    XCTAssertEqual(store.configuration.movementSpeed, 1.4, accuracy: 0.001)
    XCTAssertEqual(store.configuration.sparkIntensity, 0.75, accuracy: 0.001)

    let persistedData = try XCTUnwrap(
      defaults.data(forKey: StatusBarPetSettingsStore.defaultsKey))
    let decoded = try XCTUnwrap(
      StatusBarPetConfigurationPersistence.decode(persistedData))
    XCTAssertEqual(decoded, persisted)
  }

  func testNormalModeUsesPersistedConfiguration() throws {
    var persisted = StatusBarPetConfiguration.electricDragon
    persisted.isEnabled = true
    persisted.size = .tiny
    persisted.movementSpeed = 0.8
    defaults.set(
      try XCTUnwrap(StatusBarPetConfigurationPersistence.encode(persisted)),
      forKey: StatusBarPetSettingsStore.defaultsKey)

    let store = StatusBarPetSettingsStore(
      defaults: defaults,
      runtimeSmokeEnabled: false)

    XCTAssertEqual(store.configuration, persisted)
  }
}
