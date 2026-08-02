import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarPetController {
  private let state = StatusBarPetState()
  private var panel: NSPanel?
  private var timerCancellable: AnyCancellable?
  private var activeScreen: NSScreen?
  private var anchorFrame: NSRect?
  private var lastTick = Date.timeIntervalSinceReferenceDate
  private var targetX: Double?
  private var nextRoamDecision = 0.0

  var isVisibleForTesting: Bool { panel?.isVisible ?? false }

  func update(
    preferredScreen: NSScreen?,
    anchorFrame: NSRect?,
    configuration: StatusBarPetConfiguration
  ) {
    let normalized = StatusBarPetConfigurationPolicy.normalized(configuration)
    state.configuration = normalized
    self.anchorFrame = anchorFrame

    guard normalized.isEnabled else {
      hide()
      return
    }

    guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else {
      hide()
      return
    }

    activeScreen = screen
    ensurePanel()
    layoutPanel(on: screen)
    seedPositionIfNeeded(on: screen)
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
    let barHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
    let petHeight = state.configuration.size.height
    let panelHeight = max(48, barHeight + petHeight * 0.78)
    let frame = NSRect(
      x: screen.frame.minX,
      y: screen.frame.maxY - panelHeight,
      width: screen.frame.width,
      height: panelHeight)
    panel?.setFrame(frame, display: true)
    state.petY = CGFloat(max(petHeight / 2 + 1, min(barHeight * 0.48, panelHeight - petHeight / 2)))
  }

  private func seedPositionIfNeeded(on screen: NSScreen) {
    guard state.petX <= 0 || state.petX > screen.frame.width else { return }
    let anchorX = localAnchorX(on: screen)
    let bounds = StatusBarPetMotionRules.roamBounds(
      screenWidth: screen.frame.width,
      anchorX: anchorX)
    state.petX = CGFloat(StatusBarPetMotionRules.clamped(anchorX ?? bounds.upperBound - 42, to: bounds))
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
      state.configuration.isEnabled,
      panel?.isVisible == true
    else {
      return
    }

    let deltaTime = min(max(now - lastTick, 0), 0.1)
    lastTick = now

    let mouse = NSEvent.mouseLocation
    let cursorX = mouse.x - screen.frame.minX
    let cursorDistanceFromTop = screen.frame.maxY - mouse.y
    let anchorX = localAnchorX(on: screen)
    let bounds = StatusBarPetMotionRules.roamBounds(
      screenWidth: screen.frame.width,
      anchorX: anchorX)
    let prefersReducedMotion = state.configuration.respectReducedMotion
      && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    let isPlaying = !prefersReducedMotion
      && StatusBarPetMotionRules.shouldPlay(
        petX: Double(state.petX),
        cursorX: cursorX,
        cursorDistanceFromTop: cursorDistanceFromTop,
        interactionEnabled: state.configuration.cursorInteractionEnabled)

    if isPlaying {
      let offset = cursorX >= Double(state.petX) ? -22.0 : 22.0
      targetX = StatusBarPetMotionRules.clamped(cursorX + offset, to: bounds)
      state.cursorPoint = CGPoint(
        x: cursorX,
        y: min(max(cursorDistanceFromTop, 0), panel?.frame.height ?? 48))
      state.cursorVisible = true
      state.activity = .playing
    } else {
      state.cursorVisible = false
      if prefersReducedMotion || !state.configuration.roamEnabled {
        targetX = StatusBarPetMotionRules.clamped(anchorX ?? Double(state.petX), to: bounds)
        state.activity = .idle
      } else if targetX == nil || now >= nextRoamDecision {
        let randomTarget = Double.random(in: bounds)
        targetX = StatusBarPetMotionRules.clamped(
          StatusBarPetMotionRules.avoidingNotch(
            target: randomTarget,
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            anchorX: anchorX),
          to: bounds)
        nextRoamDecision = now + Double.random(in: 2.8...5.4)
        state.activity = .roaming
      }
    }

    guard let targetX else { return }
    let currentX = Double(state.petX)
    let pointsPerSecond: Double
    switch state.activity {
    case .idle:
      pointsPerSecond = 26
    case .roaming:
      pointsPerSecond = 48
    case .playing:
      pointsPerSecond = 190
    }

    let nextX = StatusBarPetMotionRules.advancedX(
      current: currentX,
      target: targetX,
      pointsPerSecond: pointsPerSecond * state.configuration.movementSpeed,
      deltaTime: deltaTime)
    if abs(targetX - nextX) < 0.8, state.activity == .roaming {
      state.activity = .idle
    }
    if abs(nextX - currentX) > 0.01 {
      state.facingRight = nextX > currentX
    }
    state.petX = CGFloat(nextX)
  }

  private func localAnchorX(on screen: NSScreen) -> Double? {
    guard let anchorFrame else { return nil }
    return anchorFrame.midX - screen.frame.minX
  }
}
