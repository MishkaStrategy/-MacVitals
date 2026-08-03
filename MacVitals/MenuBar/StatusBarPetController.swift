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
  private var targetProgress: Double?
  private var nextRoamDecision = 0.0
  private var crawlPhase = 0.0
  private var smoothedVelocity = 0.0

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
    seedPositionIfNeeded(now: Date.timeIntervalSinceReferenceDate)
    startTimerIfNeeded()
    panel?.orderFrontRegardless()
  }

  func hide() {
    timerCancellable?.cancel()
    timerCancellable = nil
    panel?.orderOut(nil)
    activeScreen = nil
    targetProgress = nil
    state.cursorVisible = false
    state.activity = .idle
    state.travelVelocity = 0
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
    applyContourSample(
      progress: Double(state.contourProgress),
      panelWidth: width,
      safeAreaTop: safeAreaTop,
      petWidth: petSize.width,
      petHeight: petSize.height)
  }

  private func seedPositionIfNeeded(now: TimeInterval) {
    guard let panel else { return }
    let configuration = state.configuration
    let panelWidth = Double(panel.frame.width)
    let progress = StatusBarPetContourPath.normalizedProgress(Double(state.contourProgress))

    state.contourProgress = CGFloat(progress)
    targetProgress = progress
    nextRoamDecision = now + Double.random(in: 0.8...1.8)
    applyContourSample(
      progress: progress,
      panelWidth: panelWidth,
      safeAreaTop: Double(state.safeAreaTop),
      petWidth: configuration.size.width,
      petHeight: configuration.size.height)
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
    let petWidth = configuration.size.width
    let petHeight = configuration.size.height
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

    let currentProgress = Double(state.contourProgress)

    if isPlaying {
      targetProgress = StatusBarPetContourPath.progress(
        nearestToX: cursorX,
        panelWidth: panelWidth,
        safeAreaTop: safeAreaTop,
        petWidth: petWidth,
        petHeight: petHeight)
      state.cursorPoint = CGPoint(
        x: CGFloat(cursorX),
        y: CGFloat(min(max(cursorY, 0), Double(panel.frame.height))))
      state.cursorVisible = true
      state.activity = .playing
      nextRoamDecision = now + 1.3
    } else {
      state.cursorVisible = false

      if prefersReducedMotion || !configuration.roamEnabled {
        targetProgress = StatusBarPetContourPath.centerProgress
        state.activity = .idle
      } else if state.activity == .playing {
        targetProgress = currentProgress
        state.activity = .idle
      } else if state.activity == .roaming,
        let targetProgress,
        abs(targetProgress - currentProgress) < 0.004
      {
        self.targetProgress = currentProgress
        state.activity = .idle
        nextRoamDecision = now + Double.random(in: 1.6...4.2)
      } else if state.activity == .idle, now >= nextRoamDecision {
        targetProgress = nextAutonomousTarget(from: currentProgress)
        state.activity = .roaming
      }
    }

    guard let targetProgress else { return }

    let pointsPerSecond: Double
    switch state.activity {
    case .idle:
      pointsPerSecond = 18
    case .roaming:
      pointsPerSecond = 36
    case .playing:
      pointsPerSecond = 88
    }

    let nextProgress = StatusBarPetContourPath.advancedProgress(
      current: currentProgress,
      target: targetProgress,
      pointsPerSecond: pointsPerSecond * configuration.movementSpeed,
      deltaTime: deltaTime,
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)
    let progressDelta = nextProgress - currentProgress

    if abs(progressDelta) > 0.000_01 {
      state.facingRight = progressDelta > 0
      let pathLength = StatusBarPetContourPath.pathLength(
        panelWidth: panelWidth,
        safeAreaTop: safeAreaTop,
        petWidth: petWidth,
        petHeight: petHeight)
      let traveledPoints = abs(progressDelta) * pathLength
      crawlPhase = (crawlPhase + traveledPoints / max(petWidth * 0.44, 1))
        .truncatingRemainder(dividingBy: 1)
    }

    let instantaneousVelocity = min(
      1,
      abs(progressDelta) / max(deltaTime, 0.001) * 2.7)
    smoothedVelocity += (instantaneousVelocity - smoothedVelocity) * min(deltaTime * 10, 1)

    state.contourProgress = CGFloat(nextProgress)
    state.crawlPhase = CGFloat(crawlPhase)
    state.travelVelocity = CGFloat(smoothedVelocity)
    state.perchBlend = CGFloat(max(0, 1 - smoothedVelocity * 1.8))
    applyContourSample(
      progress: nextProgress,
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)
  }

  private func applyContourSample(
    progress: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    petWidth: Double,
    petHeight: Double
  ) {
    let sample = StatusBarPetContourPath.sample(
      progress: progress,
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)
    state.petX = CGFloat(sample.x)
    state.petY = CGFloat(sample.y)
    state.bodyRotationDegrees = sample.tangentDegrees
  }

  private func nextAutonomousTarget(from current: Double) -> Double {
    if current < 0.34 {
      return Double.random(in: 0.58...StatusBarPetContourPath.rightPerchProgress)
    }
    if current > 0.66 {
      return Double.random(in: StatusBarPetContourPath.leftPerchProgress...0.42)
    }
    return Bool.random()
      ? Double.random(in: StatusBarPetContourPath.leftPerchProgress...0.25)
      : Double.random(in: 0.75...StatusBarPetContourPath.rightPerchProgress)
  }
}
