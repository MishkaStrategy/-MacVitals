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
      let diagnosticsPath = environment["MACVITALS_NOTCH_DIAGNOSTICS_PATH"],
      !diagnosticsPath.isEmpty,
      let readyPath = environment["MACVITALS_PHYSICAL_VISUAL_READY_FILE"],
      !readyPath.isEmpty
    else {
      throw XCTSkip("Physical visual evidence paths are required")
    }

    let evidenceDirectory = URL(fileURLWithPath: evidencePath, isDirectory: true)
    try FileManager.default.createDirectory(
      at: evidenceDirectory,
      withIntermediateDirectories: true)

    guard let appDelegate = NSApp.delegate as? AppDelegate else {
      XCTFail("MacVitals AppDelegate is unavailable in the physical test host")
      return
    }
    guard let statusController: StatusItemController = reflectedChild(
      appDelegate,
      label: "statusController")
    else {
      XCTFail("Product StatusItemController was not created")
      return
    }
    guard let statusItem: NSStatusItem = reflectedChild(statusController, label: "statusItem"),
      let popover: NSPopover = reflectedChild(statusController, label: "popover"),
      let notchHUD: NotchHUDController = reflectedChild(statusController, label: "notchHUD")
    else {
      XCTFail("Product status item, popover or notch HUD controller could not be resolved")
      return
    }

    let settings = appDelegate.settings
    let originalHUDEnabled = settings.showAroundStatusBar
    let originalHUDConfiguration = settings.notchHUDConfiguration
    let originalSamplingInterval = settings.samplingInterval
    let preferredScreen = statusItem.button?.window?.screen ?? NSScreen.main
    let history = HistoricalConsumptionCenter.shared
    let historyWasCollecting = history.isCollecting

    defer {
      if popover.isShown { popover.performClose(nil) }
      MetricDetailWindowPresenter.shared.close()
      notchHUD.update(
        snapshot: appDelegate.coordinator.snapshot,
        preferredScreen: preferredScreen,
        enabled: originalHUDEnabled,
        configuration: originalHUDConfiguration)
      history.stop(flush: false)
      if historyWasCollecting {
        history.start(interval: originalSamplingInterval, initialDelay: 0)
      }
    }

    notchHUD.update(
      snapshot: appDelegate.coordinator.snapshot,
      preferredScreen: preferredScreen,
      enabled: true,
      configuration: .minimal)

    let diagnosticsURL = URL(fileURLWithPath: diagnosticsPath)
    var hud: [String: Any] = [:]
    try await waitUntil(timeout: 8) {
      guard let candidate = self.readJSONIfAvailable(diagnosticsURL),
        candidate["panelVisible"] as? Bool == true,
        candidate["frameWidth"] is Double,
        candidate["hardwareNotchWidth"] is Double
      else {
        return false
      }
      hud = candidate
      return true
    }
    try validateHUDDiagnostics(hud)

    let visibleHUDPanels = NSApp.windows.compactMap { $0 as? NSPanel }
      .filter { $0.level == .statusBar && $0.isVisible }
    XCTAssertEqual(
      visibleHUDPanels.count,
      1,
      "Accepted HUD must use one visible AppKit status-bar panel before the popover is opened")

    guard let statusButton = statusItem.button else {
      XCTFail("MacVitals status item button is missing")
      return
    }
    statusButton.performClick(nil)
    try await waitUntil(timeout: 5) { popover.isShown }
    guard let overviewView = popover.contentViewController?.view else {
      XCTFail("Product overview popover has no content view")
      return
    }

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
      coordinator: appDelegate.coordinator,
      settings: settings,
      fanControl: appDelegate.fanControl)
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
      coordinator: appDelegate.coordinator,
      settings: settings,
      fanControl: appDelegate.fanControl)
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

    let summary: [String: Any] = [
      "schemaVersion": 1,
      "result": "passed",
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
      "resourceObservationHoldSeconds": 70,
    ]
    let summaryData = try JSONSerialization.data(
      withJSONObject: summary,
      options: [.prettyPrinted, .sortedKeys])
    try summaryData.write(
      to: evidenceDirectory.appendingPathComponent("physical-visual-summary.json"),
      options: .atomic)
  }

  private func validateHUDDiagnostics(_ hud: [String: Any]) throws {
    XCTAssertEqual(hud["enabled"] as? Bool, true)
    XCTAssertEqual(hud["panelAllocated"] as? Bool, true)
    XCTAssertEqual(hud["panelVisible"] as? Bool, true)
    XCTAssertGreaterThan(hud["panelWindowNumber"] as? Int ?? 0, 0)
    XCTAssertEqual(hud["indicatorCount"] as? String, "one")
    XCTAssertEqual(hud["primaryMetric"] as? String, "cpu")
    XCTAssertEqual(hud["showValueText"] as? Bool, true)

    let safeAreaTop = try XCTUnwrap(hud["safeAreaTop"] as? Double)
    let screenX = try XCTUnwrap(hud["screenX"] as? Double)
    let screenY = try XCTUnwrap(hud["screenY"] as? Double)
    let screenWidth = try XCTUnwrap(hud["screenWidth"] as? Double)
    let screenHeight = try XCTUnwrap(hud["screenHeight"] as? Double)
    let notchCenterX = try XCTUnwrap(hud["hardwareNotchCenterX"] as? Double)
    let notchWidth = try XCTUnwrap(hud["hardwareNotchWidth"] as? Double)
    let resolvedNotchWidth = try XCTUnwrap(hud["resolvedNotchWidth"] as? Double)
    let frameX = try XCTUnwrap(hud["frameX"] as? Double)
    let frameY = try XCTUnwrap(hud["frameY"] as? Double)
    let frameWidth = try XCTUnwrap(hud["frameWidth"] as? Double)
    let frameHeight = try XCTUnwrap(hud["frameHeight"] as? Double)

    XCTAssertGreaterThan(safeAreaTop, 0, "Physical validation requires a notched display")
    XCTAssertGreaterThan(notchWidth, 0)
    XCTAssertEqual(resolvedNotchWidth, notchWidth, accuracy: 0.5)
    XCTAssertEqual(frameWidth, notchWidth + 144, accuracy: 3)
    XCTAssertEqual(frameHeight, min(max(safeAreaTop, 30), 44) + 32, accuracy: 3)
    XCTAssertEqual(frameX + frameWidth / 2, notchCenterX, accuracy: 3)
    XCTAssertEqual(frameY + frameHeight, screenY + screenHeight, accuracy: 3)
    XCTAssertGreaterThanOrEqual(frameX, screenX + 8 - 0.5)
    XCTAssertLessThanOrEqual(frameX + frameWidth, screenX + screenWidth - 8 + 0.5)

    if abs(screenWidth - 2056) <= 3 && abs(screenHeight - 1329) <= 3 {
      XCTAssertEqual(safeAreaTop, 38, accuracy: 2)
      XCTAssertEqual(notchCenterX, 1028, accuracy: 3)
      XCTAssertEqual(notchWidth, 220, accuracy: 4)
      XCTAssertEqual(frameX, 846, accuracy: 4)
      XCTAssertEqual(frameWidth, 364, accuracy: 4)
      XCTAssertEqual(frameHeight, 70, accuracy: 3)
    }
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

  private func readJSONIfAvailable(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data),
      let payload = object as? [String: Any]
    else {
      return nil
    }
    return payload
  }

  private enum ValidationError: Error {
    case timedOut
    case invalidCaptureBounds
    case invalidPNG
  }
}
