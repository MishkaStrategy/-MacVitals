import SwiftUI

nonisolated enum StatusBarPetActivity: String, Sendable {
  case idle
  case roaming
  case playing
}

@MainActor
final class StatusBarPetState: ObservableObject {
  @Published var configuration = StatusBarPetConfiguration.electricDragon
  @Published var petX: CGFloat = 0
  @Published var petY: CGFloat = 20
  @Published var panelWidth: CGFloat = 300
  @Published var safeAreaTop: CGFloat = 38
  @Published var cursorPoint = CGPoint.zero
  @Published var activity = StatusBarPetActivity.idle
  @Published var facingRight = true
  @Published var cursorVisible = false
  @Published var contourProgress: CGFloat = 0.08
  @Published var bodyRotationDegrees: Double = 0
  @Published var crawlPhase: CGFloat = 0
  @Published var travelVelocity: CGFloat = 0
  @Published var perchBlend: CGFloat = 1
}

struct StatusBarPetRootView: View {
  @ObservedObject var state: StatusBarPetState

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      let petSize = CGSize(
        width: state.configuration.size.width,
        height: state.configuration.size.height)
      let petCenter = CGPoint(
        x: state.petX,
        y: state.petY + microBob(time: time))
      let pawOffset = petSize.width * 0.31 * (state.facingRight ? 1 : -1)
      let pawPoint = CGPoint(
        x: petCenter.x + pawOffset,
        y: petCenter.y + petSize.height * 0.11)

      ZStack(alignment: .topLeading) {
        if state.cursorVisible {
          GentleElectricArc(
            from: pawPoint,
            to: state.cursorPoint,
            phase: time * 4.8)
            .stroke(
              Color.cyan.opacity(0.28 + state.configuration.sparkIntensity * 0.46),
              style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            .shadow(
              color: Color.cyan.opacity(0.24 + state.configuration.sparkIntensity * 0.34),
              radius: 3)
        }

        DetailedElectricDragonView(
          activity: state.activity,
          time: time,
          sparkIntensity: state.configuration.sparkIntensity,
          crawlPhase: state.crawlPhase,
          travelVelocity: state.travelVelocity,
          perchBlend: state.perchBlend)
          .frame(width: petSize.width, height: petSize.height)
          .scaleEffect(x: state.facingRight ? 1 : -1, y: 1)
          .rotationEffect(.degrees(state.bodyRotationDegrees), anchor: .center)
          .position(petCenter)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func microBob(time: TimeInterval) -> CGFloat {
    switch state.activity {
    case .idle:
      return CGFloat(sin(time * 1.55) * 0.34) * state.perchBlend
    case .roaming:
      return CGFloat(sin(time * 7.2 + Double(state.crawlPhase) * .pi * 2) * 0.18)
    case .playing:
      return CGFloat(sin(time * 8.8) * 0.5)
    }
  }
}

private struct GentleElectricArc: Shape {
  let from: CGPoint
  let to: CGPoint
  let phase: Double

  func path(in _: CGRect) -> Path {
    var path = Path()
    path.move(to: from)

    let segmentCount = 6
    let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
    let length = max(1, hypot(delta.x, delta.y))
    let normal = CGPoint(x: -delta.y / length, y: delta.x / length)

    for index in 1...segmentCount {
      let progress = CGFloat(index) / CGFloat(segmentCount)
      let base = CGPoint(
        x: from.x + delta.x * progress,
        y: from.y + delta.y * progress)
      let envelope = sin(progress * .pi)
      let jitter = CGFloat(sin(phase * 2 + Double(index) * 1.57)) * 2.35 * envelope
      path.addLine(to: CGPoint(
        x: base.x + normal.x * jitter,
        y: base.y + normal.y * jitter))
    }

    return path
  }
}
