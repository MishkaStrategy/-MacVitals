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
  @Published var petY: CGFloat = 18
  @Published var cursorPoint = CGPoint.zero
  @Published var activity = StatusBarPetActivity.idle
  @Published var facingRight = true
  @Published var cursorVisible = false
}

struct StatusBarPetRootView: View {
  @ObservedObject var state: StatusBarPetState

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      let petSize = CGSize(
        width: state.configuration.size.width,
        height: state.configuration.size.height)
      let bob = verticalBob(time: time)
      let petCenter = CGPoint(x: state.petX, y: state.petY + bob)
      let pawOffset = petSize.width * 0.27 * (state.facingRight ? 1 : -1)
      let pawPoint = CGPoint(
        x: petCenter.x + pawOffset,
        y: petCenter.y + petSize.height * 0.14)

      ZStack(alignment: .topLeading) {
        if state.cursorVisible {
          ElectricArcShape(
            from: pawPoint,
            to: state.cursorPoint,
            phase: time * 5)
            .stroke(
              Color.cyan.opacity(0.34 + state.configuration.sparkIntensity * 0.56),
              style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            .shadow(
              color: Color.blue.opacity(0.38 + state.configuration.sparkIntensity * 0.42),
              radius: 3 + state.configuration.sparkIntensity * 4)
        }

        ElectricDragonView(
          activity: state.activity,
          time: time,
          sparkIntensity: state.configuration.sparkIntensity)
          .frame(width: petSize.width, height: petSize.height)
          .scaleEffect(x: state.facingRight ? 1 : -1, y: 1)
          .position(petCenter)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func verticalBob(time: TimeInterval) -> CGFloat {
    switch state.activity {
    case .idle:
      return CGFloat(sin(time * 2.2) * 0.55)
    case .roaming:
      return CGFloat(abs(sin(time * 8.5)) * -1.15)
    case .playing:
      return CGFloat(sin(time * 12) * 0.9)
    }
  }
}

private struct ElectricDragonView: View {
  let activity: StatusBarPetActivity
  let time: TimeInterval
  let sparkIntensity: Double

  var body: some View {
    Canvas { context, size in
      let width = size.width
      let height = size.height
      let bounce = CGFloat(activity == .roaming ? sin(time * 8) * 0.7 : 0)
      let electricPulse = CGFloat((sin(time * 7) + 1) / 2)

      let tail = dragonTail(in: size, bounce: bounce)
      context.stroke(
        tail,
        with: .color(Color.cyan.opacity(0.18 + sparkIntensity * 0.22)),
        style: StrokeStyle(lineWidth: max(4, height * 0.23), lineCap: .round))
      context.stroke(
        tail,
        with: .linearGradient(
          Gradient(colors: [Color.indigo, Color.blue, Color.cyan]),
          startPoint: CGPoint(x: width * 0.16, y: height * 0.68),
          endPoint: CGPoint(x: width * 0.97, y: height * 0.62)),
        style: StrokeStyle(lineWidth: max(2.5, height * 0.13), lineCap: .round))

      let leftWing = wingPath(
        origin: CGPoint(x: width * 0.37, y: height * 0.43 + bounce),
        size: CGSize(width: width * 0.25, height: height * 0.34),
        flipped: false)
      let rightWing = wingPath(
        origin: CGPoint(x: width * 0.52, y: height * 0.45 + bounce),
        size: CGSize(width: width * 0.24, height: height * 0.31),
        flipped: true)
      for wing in [leftWing, rightWing] {
        context.fill(
          wing,
          with: .linearGradient(
            Gradient(colors: [Color.purple.opacity(0.9), Color.blue.opacity(0.9)]),
            startPoint: CGPoint(x: width * 0.3, y: 0),
            endPoint: CGPoint(x: width * 0.72, y: height)))
        context.stroke(
          wing,
          with: .color(Color.cyan.opacity(0.72)),
          lineWidth: max(0.7, height * 0.032))
      }

      let bodyRect = CGRect(
        x: width * 0.26,
        y: height * 0.43 + bounce,
        width: width * 0.5,
        height: height * 0.36)
      context.fill(
        Path(ellipseIn: bodyRect),
        with: .linearGradient(
          Gradient(colors: [Color.indigo, Color.blue.opacity(0.9)]),
          startPoint: bodyRect.origin,
          endPoint: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)))
      context.stroke(
        Path(ellipseIn: bodyRect),
        with: .color(Color.cyan.opacity(0.38)),
        lineWidth: max(0.7, height * 0.028))

      let headRect = CGRect(
        x: width * 0.05,
        y: height * 0.22 + bounce,
        width: width * 0.47,
        height: height * 0.5)
      context.fill(
        Path(ellipseIn: headRect),
        with: .radialGradient(
          Gradient(colors: [Color.blue.opacity(0.95), Color.indigo]),
          center: CGPoint(x: headRect.midX - headRect.width * 0.12, y: headRect.midY - headRect.height * 0.18),
          startRadius: 1,
          endRadius: headRect.width * 0.58))
      context.stroke(
        Path(ellipseIn: headRect),
        with: .color(Color.cyan.opacity(0.45)),
        lineWidth: max(0.8, height * 0.03))

      drawHorns(context: &context, size: size, bounce: bounce, pulse: electricPulse)
      drawEyes(context: &context, size: size, bounce: bounce)
      drawLegs(context: &context, size: size, bounce: bounce)
      drawSpines(context: &context, size: size, bounce: bounce, pulse: electricPulse)

      if activity == .playing {
        drawPlaySparks(
          context: &context,
          size: size,
          pulse: electricPulse,
          intensity: CGFloat(sparkIntensity))
      }
    }
  }

  private func dragonTail(in size: CGSize, bounce: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: size.width * 0.66, y: size.height * 0.63 + bounce))
    path.addCurve(
      to: CGPoint(x: size.width * 0.98, y: size.height * 0.58 + bounce),
      control1: CGPoint(x: size.width * 0.78, y: size.height * 0.92 + bounce),
      control2: CGPoint(x: size.width * 0.95, y: size.height * 0.88 + bounce))
    return path
  }

  private func wingPath(origin: CGPoint, size: CGSize, flipped: Bool) -> Path {
    let direction: CGFloat = flipped ? -1 : 1
    var path = Path()
    path.move(to: origin)
    path.addCurve(
      to: CGPoint(x: origin.x + direction * size.width, y: origin.y - size.height * 0.42),
      control1: CGPoint(x: origin.x + direction * size.width * 0.28, y: origin.y - size.height),
      control2: CGPoint(x: origin.x + direction * size.width * 0.86, y: origin.y - size.height * 0.86))
    path.addLine(to: CGPoint(x: origin.x + direction * size.width * 0.7, y: origin.y + size.height * 0.16))
    path.addLine(to: origin)
    path.closeSubpath()
    return path
  }

  private func drawHorns(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat,
    pulse: CGFloat
  ) {
    for index in 0..<3 {
      let x = size.width * (0.16 + CGFloat(index) * 0.105)
      var horn = Path()
      horn.move(to: CGPoint(x: x, y: size.height * 0.29 + bounce))
      horn.addLine(to: CGPoint(x: x + size.width * 0.045, y: size.height * (0.03 + CGFloat(index) * 0.025) + bounce))
      horn.addLine(to: CGPoint(x: x + size.width * 0.09, y: size.height * 0.32 + bounce))
      horn.closeSubpath()
      context.fill(
        horn,
        with: .linearGradient(
          Gradient(colors: [Color.blue, Color.cyan.opacity(0.85)]),
          startPoint: CGPoint(x: x, y: 0),
          endPoint: CGPoint(x: x + size.width * 0.1, y: size.height * 0.35)))
      context.stroke(
        horn,
        with: .color(Color.cyan.opacity(0.45 + Double(pulse) * 0.4)),
        lineWidth: max(0.5, size.height * 0.022))
    }
  }

  private func drawEyes(context: inout GraphicsContext, size: CGSize, bounce: CGFloat) {
    for centerX in [size.width * 0.18, size.width * 0.34] {
      let eyeRect = CGRect(
        x: centerX - size.width * 0.055,
        y: size.height * 0.39 + bounce,
        width: size.width * 0.11,
        height: size.height * 0.18)
      context.fill(Path(ellipseIn: eyeRect), with: .color(.white))
      let pupil = eyeRect.insetBy(dx: eyeRect.width * 0.32, dy: eyeRect.height * 0.22)
      context.fill(Path(ellipseIn: pupil), with: .color(Color.blue.opacity(0.95)))
      let highlight = CGRect(
        x: pupil.minX + pupil.width * 0.12,
        y: pupil.minY + pupil.height * 0.06,
        width: pupil.width * 0.32,
        height: pupil.width * 0.32)
      context.fill(Path(ellipseIn: highlight), with: .color(.white))
    }
  }

  private func drawLegs(context: inout GraphicsContext, size: CGSize, bounce: CGFloat) {
    let pawY = size.height * 0.73 + bounce
    for pawX in [size.width * 0.17, size.width * 0.47, size.width * 0.65] {
      let paw = CGRect(
        x: pawX,
        y: pawY,
        width: size.width * 0.15,
        height: size.height * 0.13)
      context.fill(Path(ellipseIn: paw), with: .color(Color.indigo))
      context.stroke(
        Path(ellipseIn: paw),
        with: .color(Color.cyan.opacity(0.45)),
        lineWidth: max(0.5, size.height * 0.02))
    }
  }

  private func drawSpines(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat,
    pulse: CGFloat
  ) {
    for index in 0..<5 {
      let x = size.width * (0.48 + CGFloat(index) * 0.08)
      var spine = Path()
      spine.move(to: CGPoint(x: x, y: size.height * 0.49 + bounce))
      spine.addLine(to: CGPoint(x: x + size.width * 0.035, y: size.height * 0.34 + bounce))
      spine.addLine(to: CGPoint(x: x + size.width * 0.07, y: size.height * 0.52 + bounce))
      spine.closeSubpath()
      context.fill(
        spine,
        with: .color(Color.cyan.opacity(0.42 + Double(pulse) * 0.4)))
    }
  }

  private func drawPlaySparks(
    context: inout GraphicsContext,
    size: CGSize,
    pulse: CGFloat,
    intensity: CGFloat
  ) {
    let origin = CGPoint(x: size.width * 0.46, y: size.height * 0.78)
    for index in 0..<4 {
      let angle = CGFloat(index) * .pi / 2 + pulse * 0.6
      let distance = size.height * (0.1 + CGFloat(index % 2) * 0.04)
      let point = CGPoint(
        x: origin.x + cos(angle) * distance,
        y: origin.y + sin(angle) * distance)
      let radius = max(0.6, size.height * (0.014 + intensity * 0.018))
      context.fill(
        Path(ellipseIn: CGRect(
          x: point.x - radius,
          y: point.y - radius,
          width: radius * 2,
          height: radius * 2)),
        with: .color(Color.cyan.opacity(0.52 + Double(intensity) * 0.42)))
    }
  }
}

private struct ElectricArcShape: Shape {
  let from: CGPoint
  let to: CGPoint
  let phase: Double

  func path(in _: CGRect) -> Path {
    var path = Path()
    path.move(to: from)

    let segmentCount = 7
    let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
    let length = max(1, hypot(delta.x, delta.y))
    let normal = CGPoint(x: -delta.y / length, y: delta.x / length)

    for index in 1...segmentCount {
      let progress = CGFloat(index) / CGFloat(segmentCount)
      let base = CGPoint(
        x: from.x + delta.x * progress,
        y: from.y + delta.y * progress)
      let envelope = sin(progress * .pi)
      let jitter = CGFloat(sin(phase * 2.3 + Double(index) * 1.77)) * 4.2 * envelope
      path.addLine(to: CGPoint(
        x: base.x + normal.x * jitter,
        y: base.y + normal.y * jitter))
    }
    return path
  }
}
