import AppKit
import Foundation
import XCTest

@testable import MacVitals

@MainActor
final class PhysicalVisualAcceptanceTests: XCTestCase {
  func testAcceptedHUDOverviewAndHistorySurfaces() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let evidencePath = environment["MACVITALS_PHYSICAL_VISUAL_EVIDENCE_DIR"],
      !evidencePath.isEmpty,
      let readyPath = environment["MACVITALS_PHYSICAL_VISUAL_READY_FILE"],
      !readyPath.isEmpty
    else {
      throw XCTSkip("Physical visual evidence paths are required")
    }

    let evidenceDirectory = URL(fileURLWithPath: evidencePath, isDirectory: true)
    try FileManager.default.createDirectory(
      at: evidenceDirectory,
      withIntermediateDirectories: true)

    let preferencesDomain = try XCTUnwrap(Bundle.main.bundleIdentifier)
    let initialPreferences =
      UserDefaults.standard.persistentDomain(forName: preferencesDomain) ?? [:]

    let settings = SettingsStore()
    let coordinator = MetricsCoordinator()
    let fanControl = FanControlClient()
    let statusController = StatusItemController(
      coordinator: coordinator,
      settings: settings,
      fanControl: fanControl)
    coordinator.start()
    fanControl.refreshStatus()

    guard let statusItem: NSStatusItem = reflectedChild(statusController, label: "statusItem"),
      let popover: NSPopover = reflectedChild(statusController, label: "popover"),
      let notchHUD: NotchHUDController = reflectedChild(statusController, label: "notchHUD")
    else {
      XCTFail("Product status item, popover or notch HUD controller could not be resolved")
      return
    }

    let originalSamplingInterval = settings.samplingInterval
    let preferredScreen = statusItem.button?.window?.screen ?? NSScreen.main
    let history = HistoricalConsumptionCenter.shared
    let historyWasCollecting = history.isCollecting
    var overviewWindow: NSWindow?

    defer {
      overviewWindow?.close()
      MetricDetailWindowPresenter.shared.close()
      notchHUD.hide()
      history.stop(flush: false)
      if historyWasCollecting {
        history.start(interval: originalSamplingInterval, initialDelay: 0)
      }
      coordinator.stop()
      fanControl.invalidateConnection()
      let finalPreferences =
        UserDefaults.standard.persistentDomain(forName: preferencesDomain) ?? [:]
      XCTAssertTrue(
        preferenceDomainsEqual(initialPreferences, finalPreferences),
        "Physical visual validation must not mutate the MacVitals preferences domain")
    }

    let validationConfiguration = NotchHUDConfiguration.minimal
    XCTAssertEqual(validationConfiguration.metric, .cpu)
    XCTAssertEqual(validationConfiguration.indicatorCount, .one)
    XCTAssertNil(validationConfiguration.secondaryMetric)
    XCTAssertTrue(validationConfiguration.showValueText)

    let physicalScreen = try XCTUnwrap(
      preferredScreen,
      "Physical HUD validation requires the status-item or main display")
    notchHUD.update(
      snapshot: coordinator.snapshot,
      preferredScreen: physicalScreen,
      enabled: true,
      configuration: validationConfiguration)

    var ownedHUDPanel: NSPanel?
    try await waitUntil(timeout: 8) {
      ownedHUDPanel = self.reflectedChild(notchHUD, label: "panel")
      return ownedHUDPanel?.isVisible == true
    }
    let hudPanel = try XCTUnwrap(ownedHUDPanel)
    let hud = try validateOwnedHUD(
      panel: hudPanel,
      screen: physicalScreen,
      configuration: validationConfiguration)
    try writeJSON(
      hud,
      to: evidenceDirectory.appendingPathComponent("validation-owned-hud.json"))

    let visibleHUDPanels = NSApp.windows.compactMap { $0 as? NSPanel }
      .filter {
        $0.windowNumber == hudPanel.windowNumber && $0.level == .statusBar && $0.isVisible
      }
    XCTAssertEqual(
      visibleHUDPanels.count,
      1,
      "Accepted HUD controller must own exactly one visible AppKit status-bar panel")

    // XCTest creates a disconnected status-item scene for secondary NSStatusItems, so neither
    // performClick nor NSPopover.show(relativeTo:) can exercise that scene. Render the exact
    // product popover content controller in a validation-owned window instead. This preserves the
    // production OverviewView tree and its onAppear sampling lifecycle without pretending to test
    // status-item scene dispatch, which is covered separately by UI/runtime gates.
    let overviewController = try XCTUnwrap(popover.contentViewController)
    let physicalOverviewWindow = NSWindow(contentViewController: overviewController)
    physicalOverviewWindow.title = "MacVitals Physical Overview"
    physicalOverviewWindow.styleMask = [.titled, .closable, .resizable]
    physicalOverviewWindow.setContentSize(popover.contentSize)
    physicalOverviewWindow.isReleasedWhenClosed = false
    physicalOverviewWindow.center()
    overviewWindow = physicalOverviewWindow
    physicalOverviewWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    try await waitUntil(timeout: 5) { physicalOverviewWindow.isVisible }
    let overviewView = overviewController.view

    let network = NetworkTrafficMonitor.shared
    let storage = StorageUsageMonitor.shared
    history.stop(flush: false)
    history.start(interval: 1, initialDelay: 0)

    try await waitUntil(timeout: 12) {
      network.snapshot != nil && network.history.count >= 2
        && storage.snapshot != nil && storage.history.count >= 2
    }
    let historyRevision = history.revision
    try await waitUntil(timeout: 12) { history.revision > historyRevision }

    try capture(view: overviewView, to: evidenceDirectory.appendingPathComponent("overview.png"))

    SupplementalMetricTabbedWindowPresenter.shared.show(
      kind: .network,
      settings: settings,
      networkMonitor: network,
      storageMonitor: storage)
    let networkWindow = try await waitForWindow(title: NetworkL10n.string("Network"), timeout: 5)
    try capture(
      view: try XCTUnwrap(networkWindow.contentView),
      to: evidenceDirectory.appendingPathComponent("network-history.png"))

    SupplementalMetricTabbedWindowPresenter.shared.show(
      kind: .storage,
      settings: settings,
      networkMonitor: network,
      storageMonitor: storage)
    let storageWindow = try await waitForWindow(title: StorageL10n.string("Storage"), timeout: 5)
    try capture(
      view: try XCTUnwrap(storageWindow.contentView),
      to: evidenceDirectory.appendingPathComponent("storage-history.png"))
    storageWindow.close()

    let memoryLeaders = await history.leaders(metric: .memory, range: .oneHour)
    XCTAssertFalse(memoryLeaders.isEmpty, "Historical memory leaders must be available")

    MetricDetailWindowPresenter.shared.show(
      kind: .memory,
      coordinator: coordinator,
      settings: settings,
      fanControl: fanControl)
    let memoryWindow = try await waitForWindow(title: L10n.string("Memory"), timeout: 5)
    let tabLabels = [
      ConsumptionHistoryL10n.string("Overview"),
      ConsumptionHistoryL10n.string("Consumption leaders"),
    ]
    let segmented = try XCTUnwrap(
      findSegmentedControl(in: try XCTUnwrap(memoryWindow.contentView), labels: tabLabels),
      "Metric detail window did not expose the Overview / Consumption leaders segmented control")
    segmented.selectedSegment = 1
    _ = segmented.sendAction(segmented.action, to: segmented.target)
    try await Task.sleep(for: .seconds(2))
    try capture(
      view: try XCTUnwrap(memoryWindow.contentView),
      to: evidenceDirectory.appendingPathComponent("historical-leaders.png"))

    MetricDetailWindowPresenter.shared.show(
      kind: .fans,
      coordinator: coordinator,
      settings: settings,
      fanControl: fanControl)
    let fanWindow = try await waitForWindow(title: L10n.string("Fans"), timeout: 5)
    try capture(
      view: try XCTUnwrap(fanWindow.contentView),
      to: evidenceDirectory.appendingPathComponent("fan-read-only.png"))

    let networkSnapshot = try XCTUnwrap(network.snapshot)
    let downloadRate = try XCTUnwrap(networkSnapshot.downloadBytesPerSecond)
    let uploadRate = try XCTUnwrap(networkSnapshot.uploadBytesPerSecond)
    let storageSnapshot = try XCTUnwrap(storage.snapshot)

    try Data("surfaces-ready\n".utf8).write(
      to: URL(fileURLWithPath: readyPath),
      options: .atomic)

    try await Task.sleep(for: .seconds(70))

    let preferencesAfterObservation =
      UserDefaults.standard.persistentDomain(forName: preferencesDomain) ?? [:]
    guard preferenceDomainsEqual(initialPreferences, preferencesAfterObservation) else {
      XCTFail("Physical visual validation changed the MacVitals preferences domain")
      throw ValidationError.preferencesChanged
    }

    let summary: [String: Any] = [
      "schemaVersion": 1,
      "result": "passed",
      "validationProductGraph":
        "StatusItemController+MetricsCoordinator+SettingsStore+FanControlClient",
      "overviewPresentation": "product-popover-content-in-validation-window",
      "screenCount": NSScreen.screens.count,
      "hudPanelCountBeforePopover": visibleHUDPanels.count,
      "hud": hud,
      "network": [
        "interface": networkSnapshot.interfaceName,
        "historyCount": network.history.count,
        "receivedBytes": networkSnapshot.receivedBytes,
        "sentBytes": networkSnapshot.sentBytes,
        "downloadBytesPerSecond": downloadRate,
        "uploadBytesPerSecond": uploadRate,
      ],
      "storage": [
        "volume": storageSnapshot.volumeName,
        "historyCount": storage.history.count,
        "usedBytes": storageSnapshot.usedBytes,
        "availableBytes": storageSnapshot.availableBytes,
        "totalBytes": storageSnapshot.totalBytes,
        "usedFraction": storageSnapshot.usedFraction,
      ],
      "historicalConsumption": [
        "revision": history.revision,
        "memoryLeaderCount": memoryLeaders.count,
        "firstRecordedAtPresent": history.historyStartedAt != nil,
      ],
      "captures": [
        "overview.png",
        "network-history.png",
        "storage-history.png",
        "historical-leaders.png",
        "fan-read-only.png",
      ],
      "captureScope": "MacVitals-owned window content only; no desktop capture",
      "preferencesWrittenByValidation": false,
      "preferencesUnchangedVerified": true,
      "resourceObservationHoldSeconds": 70,
    ]
    try writeJSON(
      summary,
      to: evidenceDirectory.appendingPathComponent("physical-visual-summary.json"))
  }

  private func validateOwnedHUD(
    panel: NSPanel,
    screen: NSScreen,
    configuration: NotchHUDConfiguration
  ) throws -> [String: Any] {
    let safeAreaTop = screen.safeAreaInsets.top
    let hardwareGeometry = try XCTUnwrap(
      NotchHUDLayout.hardwareNotchGeometry(
        screenFrame: screen.frame,
        safeAreaTop: safeAreaTop,
        auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
        auxiliaryTopRightArea: screen.auxiliaryTopRightArea),
      "Physical validation requires a display with hardware notch geometry")
    let expectedFrame = NotchHUDLayout.panelFrame(
      for: screen.frame,
      safeAreaTop: safeAreaTop,
      configuration: configuration,
      notchGeometry: hardwareGeometry)
    let frame = panel.frame

    XCTAssertTrue(panel.isVisible)
    XCTAssertEqual(panel.level, .statusBar)
    XCTAssertGreaterThan(panel.windowNumber, 0)
    XCTAssertEqual(configuration.indicatorCount, .one)
    XCTAssertEqual(configuration.metric, .cpu)
    XCTAssertTrue(configuration.showValueText)
    XCTAssertGreaterThan(safeAreaTop, 0)
    XCTAssertGreaterThan(hardwareGeometry.width, 0)
    XCTAssertEqual(frame.minX, expectedFrame.minX, accuracy: 0.5)
    XCTAssertEqual(frame.minY, expectedFrame.minY, accuracy: 0.5)
    XCTAssertEqual(frame.width, expectedFrame.width, accuracy: 0.5)
    XCTAssertEqual(frame.height, expectedFrame.height, accuracy: 0.5)
    XCTAssertEqual(frame.midX, hardwareGeometry.centerX, accuracy: 3)
    XCTAssertEqual(frame.maxY, screen.frame.maxY, accuracy: 3)
    XCTAssertGreaterThanOrEqual(frame.minX, screen.frame.minX + 8 - 0.5)
    XCTAssertLessThanOrEqual(frame.maxX, screen.frame.maxX - 8 + 0.5)

    if abs(screen.frame.width - 2056) <= 3 && abs(screen.frame.height - 1329) <= 3 {
      XCTAssertEqual(safeAreaTop, 38, accuracy: 2)
      XCTAssertEqual(hardwareGeometry.centerX, 1028, accuracy: 3)
      XCTAssertEqual(hardwareGeometry.width, 220, accuracy: 4)
      XCTAssertEqual(frame.minX, 846, accuracy: 4)
      XCTAssertEqual(frame.width, 364, accuracy: 4)
      XCTAssertEqual(frame.height, 70, accuracy: 3)
    }

    return [
      "source": "validation-owned-NotchHUDController-panel",
      "enabled": true,
      "panelAllocated": true,
      "panelVisible": panel.isVisible,
      "panelWindowNumber": panel.windowNumber,
      "indicatorCount": configuration.indicatorCount.rawValue,
      "primaryMetric": configuration.metric.rawValue,
      "secondaryMetric": configuration.secondaryMetric?.rawValue ?? NSNull(),
      "showValueText": configuration.showValueText,
      "showSensorName": configuration.showSensorName,
      "safeAreaTop": safeAreaTop,
      "screenX": screen.frame.minX,
      "screenY": screen.frame.minY,
      "screenWidth": screen.frame.width,
      "screenHeight": screen.frame.height,
      "hardwareNotchCenterX": hardwareGeometry.centerX,
      "hardwareNotchWidth": hardwareGeometry.width,
      "resolvedNotchWidth": hardwareGeometry.width,
      "frameX": frame.minX,
      "frameY": frame.minY,
      "frameWidth": frame.width,
      "frameHeight": frame.height,
    ]
  }

  private func waitForWindow(title: String, timeout: TimeInterval) async throws -> NSWindow {
    var resolved: NSWindow?
    try await waitUntil(timeout: timeout) {
      resolved = NSApp.windows.first { $0.title == title && $0.isVisible }
      return resolved != nil
    }
    return try XCTUnwrap(resolved)
  }

  private func waitUntil(
    timeout: TimeInterval,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("Timed out waiting for physical visual state")
    throw ValidationError.timedOut
  }

  private func capture(view: NSView, to url: URL) throws {
    view.layoutSubtreeIfNeeded()
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds)
    else {
      throw ValidationError.invalidCaptureBounds
    }
    view.cacheDisplay(in: bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]), data.count > 1_024 else {
      throw ValidationError.invalidPNG
    }
    try data.write(to: url, options: .atomic)
  }

  private func findSegmentedControl(in view: NSView, labels: [String]) -> NSSegmentedControl? {
    if let control = view as? NSSegmentedControl,
      control.segmentCount == labels.count,
      labels.indices.allSatisfy({ control.label(forSegment: $0) == labels[$0] })
    {
      return control
    }
    for subview in view.subviews {
      if let found = findSegmentedControl(in: subview, labels: labels) {
        return found
      }
    }
    return nil
  }

  private func reflectedChild<T>(_ object: Any, label: String) -> T? {
    for child in Mirror(reflecting: object).children where child.label == label {
      return unwrapOptional(child.value) as? T
    }
    return nil
  }

  private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first?.value
  }

  private func preferenceDomainsEqual(
    _ lhs: [String: Any],
    _ rhs: [String: Any]
  ) -> Bool {
    NSDictionary(dictionary: lhs).isEqual(NSDictionary(dictionary: rhs))
  }

  private func writeJSON(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(
      withJSONObject: value,
      options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
  }

  private enum ValidationError: Error {
    case timedOut
    case invalidCaptureBounds
    case invalidPNG
    case preferencesChanged
  }
}
