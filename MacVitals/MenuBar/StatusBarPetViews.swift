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
      let pawOffset = petSize.width * 0.22 * (state.facingRight ? 1 : -1)
      let pawPoint = CGPoint(
        x: petCenter.x + pawOffset,
        y: petCenter.y + petSize.height * 0.08)

      ZStack(alignment: .topLeading) {
        if state.cursorVisible {
          GentleElectricArc(
            from: pawPoint,
            to: state.cursorPoint,
            phase: time * 4.2)
            .stroke(
              Color.cyan.opacity(0.26 + state.configuration.sparkIntensity * 0.42),
              style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            .shadow(
              color: Color.cyan.opacity(0.22 + state.configuration.sparkIntensity * 0.3),
              radius: 2.5)
        }

        BabyElectricDragonView(
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
      return CGFloat(sin(time * 1.8) * 0.25)
    case .roaming:
      return CGFloat(abs(sin(time * 6.5)) * -0.55)
    case .playing:
      return CGFloat(sin(time * 8.5) * 0.45)
    }
  }
}

private struct BabyElectricDragonView: View {
  let activity: StatusBarPetActivity
  let time: TimeInterval
  let sparkIntensity: Double

  var body: some View {
    Canvas { context, size in
      let width = size.width
      let height = size.height
      let bounce = CGFloat(activity == .roaming ? sin(time * 6.4) * 0.35 : 0)
      let pulse = CGFloat((sin(time * 4.5) + 1) / 2)

      drawAura(context: &context, size: size, pulse: pulse)
      drawCurledTail(context: &context, size: size, bounce: bounce)
      drawWings(context: &context, size: size, bounce: bounce)
      drawBody(context: &context, size: size, bounce: bounce)
      drawHead(context: &context, size: size, bounce: bounce)
      drawSoftHorns(context: &context, size: size, bounce: bounce)
      drawFace(context: &context, size: size, bounce: bounce)
      drawPaws(context: &context, size: size, bounce: bounce)

      if activity == .playing {
        drawTinySparks(
          context: &context,
          size: size,
          pulse: pulse,
          intensity: CGFloat(sparkIntensity))
      }

      _ = width
      _ = height
    }
  }

  private func drawAura(
    context: inout GraphicsContext,
    size: CGSize,
    pulse: CGFloat
  ) {
    let aura = CGRect(
      x: size.width * 0.08,
      y: size.height * 0.08,
      width: size.width * 0.84,
      height: size.height * 0.82)
    context.fill(
      Path(ellipseIn: aura),
      with: .radialGradient(
        Gradient(colors: [
          Color.cyan.opacity(0.08 + Double(pulse) * 0.08),
          .clear,
        ]),
        center: CGPoint(x: aura.midX, y: aura.midY),
        startRadius: 1,
        endRadius: aura.width * 0.55))
  }

  private func drawCurledTail(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    var tail = Path()
    tail.move(to: CGPoint(x: size.width * 0.64, y: size.height * 0.61 + bounce))
    tail.addCurve(
      to: CGPoint(x: size.width * 0.9, y: size.height * 0.68 + bounce),
      control1: CGPoint(x: size.width * 0.82, y: size.height * 0.94 + bounce),
      control2: CGPoint(x: size.width * 1.02, y: size.height * 0.84 + bounce))
    tail.addCurve(
      to: CGPoint(x: size.width * 0.78, y: size.height * 0.55 + bounce),
      control1: CGPoint(x: size.width * 0.86, y: size.height * 0.56 + bounce),
      control2: CGPoint(x: size.width * 0.78, y: size.height * 0.5 + bounce))

    context.stroke(
      tail,
      with: .color(Color.cyan.opacity(0.16)),
      style: StrokeStyle(lineWidth: max(3.6, size.height * 0.2), lineCap: .round))
    context.stroke(
      tail,
      with: .linearGradient(
        Gradient(colors: [Color.indigo.opacity(0.88), Color.blue.opacity(0.9)]),
        startPoint: CGPoint(x: size.width * 0.6, y: size.height),
        endPoint: CGPoint(x: size.width, y: size.height * 0.5)),
      style: StrokeStyle(lineWidth: max(2.3, size.height * 0.12), lineCap: .round))
  }

  private func drawWings(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    for (originX, direction) in [(0.38, -1.0), (0.61, 1.0)] {
      let x = size.width * CGFloat(originX)
      let sign = CGFloat(direction)
      var wing = Path()
      wing.move(to: CGPoint(x: x, y: size.height * 0.47 + bounce))
      wing.addCurve(
        to: CGPoint(x: x + sign * size.width * 0.16, y: size.height * 0.35 + bounce),
        control1: CGPoint(x: x + sign * size.width * 0.04, y: size.height * 0.25 + bounce),
        control2: CGPoint(x: x + sign * size.width * 0.14, y: size.height * 0.27 + bounce))
      wing.addCurve(
        to: CGPoint(x: x, y: size.height * 0.58 + bounce),
        control1: CGPoint(x: x + sign * size.width * 0.17, y: size.height * 0.48 + bounce),
        control2: CGPoint(x: x + sign * size.width * 0.08, y: size.height * 0.58 + bounce))
      wing.closeSubpath()
      context.fill(
        wing,
        with: .linearGradient(
          Gradient(colors: [Color.purple.opacity(0.55), Color.cyan.opacity(0.45)]),
          startPoint: CGPoint(x: x, y: size.height * 0.24),
          endPoint: CGPoint(x: x, y: size.height * 0.6)))
    }
  }

  private func drawBody(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    let body = CGRect(
      x: size.width * 0.28,
      y: size.height * 0.42 + bounce,
      width: size.width * 0.5,
      height: size.height * 0.4)
    context.fill(
      Path(ellipseIn: body),
      with: .linearGradient(
        Gradient(colors: [Color.indigo.opacity(0.92), Color.blue.opacity(0.88)]),
        startPoint: body.origin,
        endPoint: CGPoint(x: body.maxX, y: body.maxY)))
    context.stroke(
      Path(ellipseIn: body),
      with: .color(Color.cyan.opacity(0.24)),
      lineWidth: max(0.45, size.height * 0.02))

    let belly = CGRect(
      x: size.width * 0.34,
      y: size.height * 0.54 + bounce,
      width: size.width * 0.31,
      height: size.height * 0.2)
    context.fill(Path(ellipseIn: belly), with: .color(Color.cyan.opacity(0.16)))
  }

  private func drawHead(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    let head = CGRect(
      x: size.width * 0.08,
      y: size.height * 0.18 + bounce,
      width: size.width * 0.55,
      height: size.height * 0.53)
    context.fill(
      Path(ellipseIn: head),
      with: .radialGradient(
        Gradient(colors: [Color.blue.opacity(0.94), Color.indigo.opacity(0.92)]),
        center: CGPoint(x: head.midX - head.width * 0.12, y: head.midY - head.height * 0.15),
        startRadius: 1,
        endRadius: head.width * 0.62))
    context.stroke(
      Path(ellipseIn: head),
      with: .color(Color.cyan.opacity(0.28)),
      lineWidth: max(0.5, size.height * 0.022))
  }

  private func drawSoftHorns(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    for x in [size.width * 0.19, size.width * 0.43] {
      let horn = CGRect(
        x: x,
        y: size.height * 0.08 + bounce,
        width: size.width * 0.11,
        height: size.height * 0.2)
      context.fill(
        Path(ellipseIn: horn),
        with: .linearGradient(
          Gradient(colors: [Color.lavender, Color.cyan.opacity(0.82)]),
          startPoint: horn.origin,
          endPoint: CGPoint(x: horn.maxX, y: horn.maxY)))
    }
  }

  private func drawFace(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    for centerX in [size.width * 0.24, size.width * 0.43] {
      let eye = CGRect(
        x: centerX - size.width * 0.062,
        y: size.height * 0.35 + bounce,
        width: size.width * 0.124,
        height: size.height * 0.18)
      context.fill(Path(ellipseIn: eye), with: .color(Color.white.opacity(0.96)))
      let pupil = eye.insetBy(dx: eye.width * 0.28, dy: eye.height * 0.2)
      context.fill(Path(ellipseIn: pupil), with: .color(Color.indigo.opacity(0.96)))
      let highlight = CGRect(
        x: pupil.minX + pupil.width * 0.08,
        y: pupil.minY + pupil.height * 0.08,
        width: pupil.width * 0.38,
        height: pupil.width * 0.38)
      context.fill(Path(ellipseIn: highlight), with: .color(.white))
    }

    for x in [size.width * 0.16, size.width * 0.49] {
      let cheek = CGRect(
        x: x,
        y: size.height * 0.54 + bounce,
        width: size.width * 0.07,
        height: size.height * 0.045)
      context.fill(Path(ellipseIn: cheek), with: .color(Color.pink.opacity(0.38)))
    }

    var smile = Path()
    smile.move(to: CGPoint(x: size.width * 0.29, y: size.height * 0.57 + bounce))
    smile.addQuadCurve(
      to: CGPoint(x: size.width * 0.39, y: size.height * 0.57 + bounce),
      control: CGPoint(x: size.width * 0.34, y: size.height * 0.64 + bounce))
    context.stroke(
      smile,
      with: .color(Color.white.opacity(0.72)),
      style: StrokeStyle(lineWidth: max(0.55, size.height * 0.026), lineCap: .round))
  }

  private func drawPaws(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    for x in [size.width * 0.22, size.width * 0.48, size.width * 0.65] {
      let paw = CGRect(
        x: x,
        y: size.height * 0.72 + bounce,
        width: size.width * 0.15,
        height: size.height * 0.12)
      context.fill(Path(ellipseIn: paw), with: .color(Color.indigo.opacity(0.92)))
      context.stroke(
        Path(ellipseIn: paw),
        with: .color(Color.cyan.opacity(0.28)),
        lineWidth: max(0.4, size.height * 0.018))
    }
  }

  private func drawTinySparks(
    context: inout GraphicsContext,
    size: CGSize,
    pulse: CGFloat,
    intensity: CGFloat
  ) {
    let origin = CGPoint(x: size.width * 0.48, y: size.height * 0.78)
    for index in 0..<3 {
      let angle = CGFloat(index) * .pi * 0.72 + pulse * 0.5
      let distance = size.height * (0.08 + CGFloat(index) * 0.018)
      let point = CGPoint(
        x: origin.x + cos(angle) * distance,
        y: origin.y + sin(angle) * distance)
      let radius = max(0.45, size.height * (0.01 + intensity * 0.012))
      context.fill(
        Path(ellipseIn: CGRect(
          x: point.x - radius,
          y: point.y - radius,
          width: radius * 2,
          height: radius * 2)),
        with: .color(Color.cyan.opacity(0.42 + Double(intensity) * 0.35)))
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

    let segmentCount = 5
    let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
    let length = max(1, hypot(delta.x, delta.y))
    let normal = CGPoint(x: -delta.y / length, y: delta.x / length)

    for index in 1...segmentCount {
      let progress = CGFloat(index) / CGFloat(segmentCount)
      let base = CGPoint(
        x: from.x + delta.x * progress,
        y: from.y + delta.y * progress)
      let envelope = sin(progress * .pi)
      let jitter = CGFloat(sin(phase * 2 + Double(index) * 1.43)) * 2.1 * envelope
      path.addLine(to: CGPoint(
        x: base.x + normal.x * jitter,
        y: base.y + normal.y * jitter))
    }
    return path
  }
}

private extension Color {
  static let lavender = Color(red: 0.74, green: 0.69, blue: 1)
}
