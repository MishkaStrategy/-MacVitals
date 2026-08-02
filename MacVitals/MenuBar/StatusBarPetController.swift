import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarPetController {
  private let state = StatusBarPetState()
  private var panel: NSPanel?
  private var timerCancellable: AnyCancellable?
  private var activeScreen: NSScreen?
  private var lastTick = Date.timeIntervalSinceReferenceDate
  private var targetX: Double?
  private var nextRoamDecision = 0.0

  var isVisibleForTesting: Bool { panel?.isVisible ?? false }

  func update(
    preferredScreen: NSScreen?,
    anchorFrame _: NSRect?,
    configuration: StatusBarPetConfiguration
  ) {
    let normalized = StatusBarPetConfigurationPolicy.normalized(configuration)
    state.configuration = normalized

    guard normalized.isEnabled else {
      hide()
      return
    }

    guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first,
      screen.safeAreaInsets.top > 0
    else {
      hide()
      return
    }

    activeScreen = screen
    ensurePanel()
    layoutPanel(on: screen)
    seedPositionIfNeeded()
    startTimerIfNeeded()
    panel?.orderFrontRegardless()
  }

  func hide() {
    timerCancellable?.cancel()
    timerCancellable = nil
    panel?.orderOut(nil)
    activeScreen = nil
    targetX = nil
    state.cursorVisible = false
    state.activity = .idle
  }

  private func ensurePanel() {
    guard panel == nil else { return }

    let petPanel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    petPanel.isOpaque = false
    petPanel.backgroundColor = .clear
    petPanel.hasShadow = false
    petPanel.isReleasedWhenClosed = false
    petPanel.hidesOnDeactivate = false
    petPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    petPanel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
    ]
    petPanel.animationBehavior = .none
    petPanel.ignoresMouseEvents = true
    petPanel.isMovable = false
    petPanel.isMovableByWindowBackground = false
    petPanel.titleVisibility = .hidden
    petPanel.titlebarAppearsTransparent = true
    petPanel.contentViewController = NSHostingController(
      rootView: StatusBarPetRootView(state: state))
    panel = petPanel
  }

  private func layoutPanel(on screen: NSScreen) {
    let safeAreaTop = Double(screen.safeAreaInsets.top)
    let petSize = state.configuration.size
    let width = StatusBarPetMotionRules.panelWidth(for: petSize)
    let height = StatusBarPetMotionRules.panelHeight(
      safeAreaTop: safeAreaTop,
      size: petSize)
    let frame = NSRect(
      x: screen.frame.midX - CGFloat(width / 2),
      y: screen.frame.maxY - CGFloat(height),
      width: CGFloat(width),
      height: CGFloat(height))

    panel?.setFrame(frame, display: true)
    state.panelWidth = CGFloat(width)
    state.safeAreaTop = CGFloat(StatusBarPetMotionRules.resolvedSafeAreaTop(safeAreaTop))

    let bounds = StatusBarPetMotionRules.roamBounds(
      panelWidth: width,
      petWidth: petSize.width)
    state.petX = CGFloat(StatusBarPetMotionRules.clamped(Double(state.petX), to: bounds))
    state.petY = CGFloat(StatusBarPetMotionRules.petY(
      x: Double(state.petX),
      panelWidth: width,
      safeAreaTop: safeAreaTop,
      petHeight: petSize.height))
  }

  private func seedPositionIfNeeded() {
    guard let panel else { return }
    let configuration = state.configuration
    let panelWidth = Double(panel.frame.width)
    let bounds = StatusBarPetMotionRules.roamBounds(
      panelWidth: panelWidth,
      petWidth: configuration.size.width)

    guard state.petX <= 0 || !bounds.contains(Double(state.petX)) else { return }
    state.petX = CGFloat(bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) * 0.18)
    state.petY = CGFloat(StatusBarPetMotionRules.petY(
      x: Double(state.petX),
      panelWidth: panelWidth,
      safeAreaTop: Double(state.safeAreaTop),
      petHeight: configuration.size.height))
    targetX = Double(state.petX)
  }

  private func startTimerIfNeeded() {
    guard timerCancellable == nil else { return }
    lastTick = Date.timeIntervalSinceReferenceDate
    timerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] date in
        self?.tick(now: date.timeIntervalSinceReferenceDate)
      }
  }

  private func tick(now: TimeInterval) {
    guard let screen = activeScreen,
      let panel,
      state.configuration.isEnabled,
      panel.isVisible,
      screen.safeAreaInsets.top > 0
    else {
      return
    }

    let deltaTime = min(max(now - lastTick, 0), 0.1)
    lastTick = now

    let configuration = state.configuration
    let panelWidth = Double(panel.frame.width)
    let safeAreaTop = Double(screen.safeAreaInsets.top)
    let bounds = StatusBarPetMotionRules.roamBounds(
      panelWidth: panelWidth,
      petWidth: configuration.size.width)
    let mouse = NSEvent.mouseLocation
    let cursorX = Double(mouse.x - panel.frame.minX)
    let cursorY = Double(panel.frame.maxY - mouse.y)
    let prefersReducedMotion = configuration.respectReducedMotion
      && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    let isPlaying = !prefersReducedMotion
      && StatusBarPetMotionRules.shouldPlay(
        petX: Double(state.petX),
        cursorX: cursorX,
        cursorY: cursorY,
        panelWidth: panelWidth,
        safeAreaTop: safeAreaTop,
        interactionEnabled: configuration.cursorInteractionEnabled)

    if isPlaying {
      let offset = cursorX >= Double(state.petX) ? -12.0 : 12.0
      targetX = StatusBarPetMotionRules.clamped(cursorX + offset, to: bounds)
      state.cursorPoint = CGPoint(
        x: CGFloat(cursorX),
        y: CGFloat(min(max(cursorY, 0), Double(panel.frame.height))))
      state.cursorVisible = true
      state.activity = .playing
    } else {
      state.cursorVisible = false
      if prefersReducedMotion || !configuration.roamEnabled {
        targetX = (bounds.lowerBound + bounds.upperBound) / 2
        state.activity = .idle
      } else if targetX == nil || now >= nextRoamDecision {
        targetX = Double.random(in: bounds)
        nextRoamDecision = now + Double.random(in: 2.4...4.8)
        state.activity = .roaming
      }
    }

    guard let targetX else { return }
    let currentX = Double(state.petX)
    let pointsPerSecond: Double
    switch state.activity {
    case .idle:
      pointsPerSecond = 20
    case .roaming:
      pointsPerSecond = 34
    case .playing:
      pointsPerSecond = 105
    }

    let nextX = StatusBarPetMotionRules.advancedX(
      current: currentX,
      target: targetX,
      pointsPerSecond: pointsPerSecond * configuration.movementSpeed,
      deltaTime: deltaTime)
    if abs(targetX - nextX) < 0.7, state.activity == .roaming {
      state.activity = .idle
    }
    if abs(nextX - currentX) > 0.01 {
      state.facingRight = nextX > currentX
    }

    state.petX = CGFloat(nextX)
    state.petY = CGFloat(StatusBarPetMotionRules.petY(
      x: nextX,
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petHeight: configuration.size.height))
  }
}
