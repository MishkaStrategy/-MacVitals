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
      let pawOffset = petSize.width * 0.28 * (state.facingRight ? 1 : -1)
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

        ElectricNotchDragonView(
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
      return CGFloat(sin(time * 1.8) * 0.35)
    case .roaming:
      return CGFloat(abs(sin(time * 6.5)) * -0.8)
    case .playing:
      return CGFloat(sin(time * 8.5) * 0.65)
    }
  }
}

struct ElectricNotchDragonView: View {
  let activity: StatusBarPetActivity
  let time: TimeInterval
  let sparkIntensity: Double

  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      let bounce = CGFloat(activity == .roaming ? sin(time * 6.4) * 0.55 : 0)
      let pulse = CGFloat((sin(time * 4.5) + 1) / 2)
      let wingLift = resolvedWingLift

      drawAura(context: &context, size: size, pulse: pulse)
      drawTail(context: &context, size: size, bounce: bounce)
      drawRearWing(context: &context, size: size, bounce: bounce, lift: wingLift)
      drawBody(context: &context, size: size, bounce: bounce)
      drawBellyScales(context: &context, size: size, bounce: bounce)
      drawNeck(context: &context, size: size, bounce: bounce)
      drawHead(context: &context, size: size, bounce: bounce)
      drawCrest(context: &context, size: size, bounce: bounce, pulse: pulse)
      drawEyeAndMuzzle(context: &context, size: size, bounce: bounce, pulse: pulse)
      drawFrontWing(context: &context, size: size, bounce: bounce, lift: wingLift)
      drawLegsAndClaws(context: &context, size: size, bounce: bounce)
      drawScaleHighlights(context: &context, size: size, bounce: bounce)
      drawEnergyChannels(context: &context, size: size, bounce: bounce, pulse: pulse)

      if activity != .idle || sparkIntensity > 0.72 {
        drawSparks(
          context: &context,
          size: size,
          pulse: pulse,
          intensity: CGFloat(sparkIntensity))
      }
    }
  }

  private var resolvedWingLift: CGFloat {
    switch activity {
    case .idle:
      return CGFloat(sin(time * 1.7) * 0.012)
    case .roaming:
      return 0.035 + CGFloat(abs(sin(time * 5.2)) * 0.045)
    case .playing:
      return 0.08 + CGFloat(sin(time * 7.5) * 0.025)
    }
  }

  private func point(
    _ x: CGFloat,
    _ y: CGFloat,
    size: CGSize,
    bounce: CGFloat = 0
  ) -> CGPoint {
    CGPoint(x: size.width * x, y: size.height * y + bounce)
  }

  private func drawAura(
    context: inout GraphicsContext,
    size: CGSize,
    pulse: CGFloat
  ) {
    let aura = CGRect(
      x: size.width * 0.03,
      y: size.height * 0.03,
      width: size.width * 0.94,
      height: size.height * 0.93)
    context.fill(
      Path(ellipseIn: aura),
      with: .radialGradient(
        Gradient(colors: [
          DragonPalette.electricBlue.opacity(0.07 + Double(pulse) * 0.07),
          DragonPalette.deepBlue.opacity(0.025),
          .clear,
        ]),
        center: CGPoint(x: aura.midX, y: aura.midY),
        startRadius: 1,
        endRadius: aura.width * 0.58))
  }

  private func drawTail(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    var tail = Path()
    tail.move(to: point(0.62, 0.58, size: size, bounce: bounce))
    tail.addCurve(
      to: point(0.92, 0.66, size: size, bounce: bounce),
      control1: point(0.76, 0.62, size: size, bounce: bounce),
      control2: point(0.9, 0.48, size: size, bounce: bounce))
    tail.addCurve(
      to: point(0.72, 0.87, size: size, bounce: bounce),
      control1: point(1.0, 0.76, size: size, bounce: bounce),
      control2: point(0.88, 0.9, size: size, bounce: bounce))
    tail.addCurve(
      to: point(0.43, 0.83, size: size, bounce: bounce),
      control1: point(0.63, 0.85, size: size, bounce: bounce),
      control2: point(0.52, 0.78, size: size, bounce: bounce))

    let glowWidth = max(4.4, size.height * 0.13)
    let bodyWidth = max(2.8, size.height * 0.082)
    context.stroke(
      tail,
      with: .color(DragonPalette.electricBlue.opacity(0.17)),
      style: StrokeStyle(lineWidth: glowWidth, lineCap: .round, lineJoin: .round))
    context.stroke(
      tail,
      with: .linearGradient(
        Gradient(colors: [
          DragonPalette.graphite,
          DragonPalette.silverBlue,
          DragonPalette.iceSilver,
        ]),
        startPoint: point(0.56, 0.52, size: size),
        endPoint: point(0.43, 0.88, size: size)),
      style: StrokeStyle(lineWidth: bodyWidth, lineCap: .round, lineJoin: .round))

    var tailChannel = Path()
    tailChannel.move(to: point(0.64, 0.57, size: size, bounce: bounce))
    tailChannel.addCurve(
      to: point(0.44, 0.82, size: size, bounce: bounce),
      control1: point(0.95, 0.64, size: size, bounce: bounce),
      control2: point(0.83, 0.92, size: size, bounce: bounce))
    context.stroke(
      tailChannel,
      with: .color(DragonPalette.electricBlue.opacity(0.76)),
      style: StrokeStyle(
        lineWidth: max(0.55, size.height * 0.013),
        lineCap: .round,
        lineJoin: .round))

    drawTailFin(context: &context, size: size, bounce: bounce)
  }

  private func drawTailFin(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    let root = point(0.44, 0.82, size: size, bounce: bounce)
    let fins: [(CGPoint, CGPoint)] = [
      (point(0.31, 0.72, size: size, bounce: bounce), point(0.39, 0.83, size: size, bounce: bounce)),
      (point(0.29, 0.84, size: size, bounce: bounce), point(0.41, 0.85, size: size, bounce: bounce)),
      (point(0.34, 0.94, size: size, bounce: bounce), point(0.43, 0.87, size: size, bounce: bounce)),
    ]

    for (tip, base) in fins {
      var fin = Path()
      fin.move(to: root)
      fin.addQuadCurve(to: tip, control: base)
      fin.addQuadCurve(to: root, control: point(
        (tip.x / size.width + 0.44) / 2,
        (tip.y - bounce) / size.height + 0.02,
        size: size,
        bounce: bounce))
      fin.closeSubpath()
      context.fill(
        fin,
        with: .linearGradient(
          Gradient(colors: [
            DragonPalette.iceSilver.opacity(0.9),
            DragonPalette.electricBlue.opacity(0.42),
          ]),
          startPoint: root,
          endPoint: tip))
      context.stroke(
        fin,
        with: .color(DragonPalette.electricBlue.opacity(0.7)),
        lineWidth: max(0.45, size.height * 0.009))
    }
  }

  private func drawRearWing(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat,
    lift: CGFloat
  ) {
    var wing = Path()
    wing.move(to: point(0.5, 0.48, size: size, bounce: bounce))
    wing.addCurve(
      to: point(0.73, 0.16 - lift, size: size, bounce: bounce),
      control1: point(0.57, 0.3, size: size, bounce: bounce),
      control2: point(0.65, 0.2 - lift, size: size, bounce: bounce))
    wing.addLine(to: point(0.78, 0.43 - lift * 0.35, size: size, bounce: bounce))
    wing.addLine(to: point(0.67, 0.35 - lift * 0.4, size: size, bounce: bounce))
    wing.addLine(to: point(0.66, 0.58, size: size, bounce: bounce))
    wing.closeSubpath()

    context.fill(
      wing,
      with: .linearGradient(
        Gradient(colors: [
          DragonPalette.deepBlue.opacity(0.74),
          DragonPalette.electricBlue.opacity(0.24),
          DragonPalette.iceSilver.opacity(0.12),
        ]),
        startPoint: point(0.53, 0.5, size: size),
        endPoint: point(0.75, 0.16, size: size)))
    context.stroke(
      wing,
      with: .color(DragonPalette.silverBlue.opacity(0.85)),
      style: StrokeStyle(
        lineWidth: max(0.7, size.height * 0.018),
        lineCap: .round,
        lineJoin: .round))

    drawWingVeins(
      context: &context,
      size: size,
      bounce: bounce,
      root: point(0.52, 0.48, size: size, bounce: bounce),
      tips: [
        point(0.71, 0.2 - lift, size: size, bounce: bounce),
        point(0.74, 0.31 - lift * 0.6, size: size, bounce: bounce),
        point(0.67, 0.38 - lift * 0.35, size: size, bounce: bounce),
      ])
  }

  private func drawFrontWing(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat,
    lift: CGFloat
  ) {
    var wing = Path()
    wing.move(to: point(0.47, 0.5, size: size, bounce: bounce))
    wing.addCurve(
      to: point(0.2, 0.2 - lift, size: size, bounce: bounce),
      control1: point(0.39, 0.33, size: size, bounce: bounce),
      control2: point(0.3, 0.21 - lift, size: size, bounce: bounce))
    wing.addLine(to: point(0.13, 0.51 - lift * 0.25, size: size, bounce: bounce))
    wing.addLine(to: point(0.28, 0.4 - lift * 0.4, size: size, bounce: bounce))
    wing.addLine(to: point(0.32, 0.6, size: size, bounce: bounce))
    wing.closeSubpath()

    context.fill(
      wing,
      with: .linearGradient(
        Gradient(colors: [
          DragonPalette.iceSilver.opacity(0.18),
          DragonPalette.electricBlue.opacity(0.34),
          DragonPalette.deepBlue.opacity(0.78),
        ]),
        startPoint: point(0.18, 0.2, size: size),
        endPoint: point(0.46, 0.58, size: size)))
    context.stroke(
      wing,
      with: .color(DragonPalette.iceSilver.opacity(0.9)),
      style: StrokeStyle(
        lineWidth: max(0.8, size.height * 0.019),
        lineCap: .round,
        lineJoin: .round))

    drawWingVeins(
      context: &context,
      size: size,
      bounce: bounce,
      root: point(0.46, 0.49, size: size, bounce: bounce),
      tips: [
        point(0.22, 0.23 - lift, size: size, bounce: bounce),
        point(0.18, 0.39 - lift * 0.45, size: size, bounce: bounce),
        point(0.3, 0.42 - lift * 0.35, size: size, bounce: bounce),
      ])
  }

  private func drawWingVeins(
    context: inout GraphicsContext,
    size: CGSize,
    bounce _: CGFloat,
    root: CGPoint,
    tips: [CGPoint]
  ) {
    for tip in tips {
      var vein = Path()
      vein.move(to: root)
      vein.addQuadCurve(
        to: tip,
        control: CGPoint(
          x: (root.x + tip.x) / 2,
          y: min(root.y, tip.y) - size.height * 0.035))
      context.stroke(
        vein,
        with: .color(DragonPalette.electricBlue.opacity(0.58)),
        style: StrokeStyle(
          lineWidth: max(0.45, size.height * 0.009),
          lineCap: .round))
    }
  }

  private func drawBody(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    var body = Path()
    body.move(to: point(0.32, 0.51, size: size, bounce: bounce))
    body.addCurve(
      to: point(0.69, 0.58, size: size, bounce: bounce),
      control1: point(0.43, 0.42, size: size, bounce: bounce),
      control2: point(0.62, 0.44, size: size, bounce: bounce))
    body.addCurve(
      to: point(0.6, 0.75, size: size, bounce: bounce),
      control1: point(0.72, 0.67, size: size, bounce: bounce),
      control2: point(0.68, 0.73, size: size, bounce: bounce))
    body.addCurve(
      to: point(0.34, 0.69, size: size, bounce: bounce),
      control1: point(0.48, 0.78, size: size, bounce: bounce),
      control2: point(0.38, 0.75, size: size, bounce: bounce))
    body.closeSubpath()

    context.fill(
      body,
      with: .linearGradient(
        Gradient(colors: [
          DragonPalette.iceSilver,
          DragonPalette.silverBlue,
          DragonPalette.graphite,
        ]),
        startPoint: point(0.31, 0.44, size: size),
        endPoint: point(0.68, 0.75, size: size)))
    context.stroke(
      body,
      with: .color(DragonPalette.electricBlue.opacity(0.34)),
      lineWidth: max(0.6, size.height * 0.012))
  }

  private func drawBellyScales(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    var belly = Path()
    belly.move(to: point(0.38, 0.55, size: size, bounce: bounce))
    belly.addCurve(
      to: point(0.59, 0.7, size: size, bounce: bounce),
      control1: point(0.47, 0.56, size: size, bounce: bounce),
      control2: point(0.57, 0.62, size: size, bounce: bounce))
    context.stroke(
      belly,
      with: .linearGradient(
        Gradient(colors: [
          DragonPalette.paleSilver.opacity(0.88),
          DragonPalette.electricBlue.opacity(0.32),
        ]),
        startPoint: point(0.38, 0.55, size: size),
        endPoint: point(0.59, 0.7, size: size)),
      style: StrokeStyle(
        lineWidth: max(2.2, size.height * 0.055),
        lineCap: .round))

    for index in 0..<5 {
      let t = CGFloat(index) / 4
      var plate = Path()
      plate.move(to: point(0.4 + t * 0.17, 0.56 + t * 0.11, size: size, bounce: bounce))
      plate.addLine(to: point(0.43 + t * 0.17, 0.58 + t * 0.11, size: size, bounce: bounce))
      context.stroke(
        plate,
        with: .color(DragonPalette.graphite.opacity(0.45)),
        lineWidth: max(0.35, size.height * 0.007))
    }
  }

  private func drawNeck(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    var neck = Path()
    neck.move(to: point(0.36, 0.57, size: size, bounce: bounce))
    neck.addCurve(
      to: point(0.29, 0.28, size: size, bounce: bounce),
      control1: point(0.34, 0.45, size: size, bounce: bounce),
      control2: point(0.34, 0.34, size: size, bounce: bounce))
    neck.addCurve(
      to: point(0.42, 0.5, size: size, bounce: bounce),
      control1: point(0.39, 0.31, size: size, bounce: bounce),
      control2: point(0.44, 0.4, size: size, bounce: bounce))
    neck.closeSubpath()

    context.fill(
      neck,
      with: .linearGradient(
        Gradient(colors: [
          DragonPalette.paleSilver,
          DragonPalette.silverBlue,
          DragonPalette.graphite,
        ]),
        startPoint: point(0.28, 0.27, size: size),
        endPoint: point(0.42, 0.56, size: size)))
    context.stroke(
      neck,
      with: .color(DragonPalette.electricBlue.opacity(0.38)),
      lineWidth: max(0.55, size.height * 0.011))
  }

  private func drawHead(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    var head = Path()
    head.move(to: point(0.17, 0.25, size: size, bounce: bounce))
    head.addCurve(
      to: point(0.42, 0.22, size: size, bounce: bounce),
      control1: point(0.25, 0.15, size: size, bounce: bounce),
      control2: point(0.36, 0.16, size: size, bounce: bounce))
    head.addCurve(
      to: point(0.37, 0.39, size: size, bounce: bounce),
      control1: point(0.45, 0.28, size: size, bounce: bounce),
      control2: point(0.42, 0.36, size: size, bounce: bounce))
    head.addCurve(
      to: point(0.14, 0.34, size: size, bounce: bounce),
      control1: point(0.29, 0.43, size: size, bounce: bounce),
      control2: point(0.2, 0.39, size: size, bounce: bounce))
    head.closeSubpath()

    context.fill(
      head,
      with: .linearGradient(
        Gradient(colors: [
          DragonPalette.paleSilver,
          DragonPalette.iceSilver,
          DragonPalette.silverBlue,
        ]),
        startPoint: point(0.14, 0.18, size: size),
        endPoint: point(0.42, 0.39, size: size)))
    context.stroke(
      head,
      with: .color(DragonPalette.electricBlue.opacity(0.42)),
      style: StrokeStyle(
        lineWidth: max(0.65, size.height * 0.013),
        lineJoin: .round))
  }

  private func drawCrest(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat,
    pulse: CGFloat
  ) {
    let spikes: [(CGPoint, CGPoint, CGPoint)] = [
      (
        point(0.22, 0.22, size: size, bounce: bounce),
        point(0.17, 0.02, size: size, bounce: bounce),
        point(0.27, 0.2, size: size, bounce: bounce)
      ),
      (
        point(0.27, 0.2, size: size, bounce: bounce),
        point(0.28, -0.03, size: size, bounce: bounce),
        point(0.32, 0.21, size: size, bounce: bounce)
      ),
      (
        point(0.32, 0.21, size: size, bounce: bounce),
        point(0.39, 0.02, size: size, bounce: bounce),
        point(0.37, 0.25, size: size, bounce: bounce)
      ),
      (
        point(0.37, 0.27, size: size, bounce: bounce),
        point(0.48, 0.13, size: size, bounce: bounce),
        point(0.4, 0.32, size: size, bounce: bounce)
      ),
    ]

    for (start, tip, end) in spikes {
      var spike = Path()
      spike.move(to: start)
      spike.addLine(to: tip)
      spike.addLine(to: end)
      spike.closeSubpath()
      context.fill(
        spike,
        with: .linearGradient(
          Gradient(colors: [
            DragonPalette.paleSilver,
            DragonPalette.electricBlue.opacity(0.64 + Double(pulse) * 0.18),
          ]),
          startPoint: end,
          endPoint: tip))
      context.stroke(
        spike,
        with: .color(DragonPalette.iceSilver.opacity(0.68)),
        lineWidth: max(0.35, size.height * 0.007))
    }
  }

  private func drawEyeAndMuzzle(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat,
    pulse: CGFloat
  ) {
    let eye = CGRect(
      x: size.width * 0.25,
      y: size.height * 0.235 + bounce,
      width: max(2.4, size.width * 0.075),
      height: max(1.7, size.height * 0.046))
    context.fill(
      Path(ellipseIn: eye.insetBy(dx: -size.width * 0.025, dy: -size.height * 0.025)),
      with: .color(DragonPalette.electricBlue.opacity(0.15 + Double(pulse) * 0.18)))
    context.fill(Path(ellipseIn: eye), with: .color(DragonPalette.eyeCore))
    context.fill(
      Path(ellipseIn: eye.insetBy(dx: eye.width * 0.3, dy: eye.height * 0.17)),
      with: .color(.white))

    var brow = Path()
    brow.move(to: point(0.23, 0.23, size: size, bounce: bounce))
    brow.addLine(to: point(0.34, 0.2, size: size, bounce: bounce))
    context.stroke(
      brow,
      with: .color(DragonPalette.graphite.opacity(0.78)),
      style: StrokeStyle(
        lineWidth: max(0.6, size.height * 0.012),
        lineCap: .round))

    var jaw = Path()
    jaw.move(to: point(0.14, 0.33, size: size, bounce: bounce))
    jaw.addQuadCurve(
      to: point(0.31, 0.36, size: size, bounce: bounce),
      control: point(0.22, 0.38, size: size, bounce: bounce))
    context.stroke(
      jaw,
      with: .color(DragonPalette.graphite.opacity(0.68)),
      style: StrokeStyle(
        lineWidth: max(0.45, size.height * 0.009),
        lineCap: .round))

    for nostrilX in [CGFloat(0.165), CGFloat(0.195)] {
      let radius = max(0.45, size.height * 0.008)
      context.fill(
        Path(ellipseIn: CGRect(
          x: size.width * nostrilX,
          y: size.height * 0.3 + bounce,
          width: radius,
          height: radius)),
        with: .color(DragonPalette.graphite.opacity(0.78)))
    }
  }

  private func drawLegsAndClaws(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    let legs: [(CGFloat, CGFloat, CGFloat)] = [
      (0.34, 0.61, 0.27),
      (0.52, 0.62, 0.49),
      (0.64, 0.64, 0.67),
    ]

    for (rootX, rootY, pawX) in legs {
      var leg = Path()
      leg.move(to: point(rootX, rootY, size: size, bounce: bounce))
      leg.addCurve(
        to: point(pawX, 0.79, size: size, bounce: bounce),
        control1: point(rootX - 0.01, 0.69, size: size, bounce: bounce),
        control2: point(pawX, 0.72, size: size, bounce: bounce))
      context.stroke(
        leg,
        with: .linearGradient(
          Gradient(colors: [
            DragonPalette.silverBlue,
            DragonPalette.graphite,
          ]),
          startPoint: point(rootX, rootY, size: size),
          endPoint: point(pawX, 0.79, size: size)),
        style: StrokeStyle(
          lineWidth: max(2.0, size.height * 0.048),
          lineCap: .round))

      for clawIndex in 0..<3 {
        let clawX = pawX - 0.025 + CGFloat(clawIndex) * 0.025
        var claw = Path()
        claw.move(to: point(clawX, 0.77, size: size, bounce: bounce))
        claw.addLine(to: point(clawX + 0.012, 0.86, size: size, bounce: bounce))
        claw.addLine(to: point(clawX + 0.022, 0.78, size: size, bounce: bounce))
        claw.closeSubpath()
        context.fill(claw, with: .color(DragonPalette.paleSilver.opacity(0.92)))
      }
    }
  }

  private func drawScaleHighlights(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat
  ) {
    let rows: [(CGFloat, CGFloat, Int)] = [
      (0.39, 0.5, 5),
      (0.42, 0.56, 6),
      (0.45, 0.62, 5),
    ]

    for (startX, y, count) in rows {
      for index in 0..<count {
        let x = startX + CGFloat(index) * 0.045
        var scale = Path()
        scale.move(to: point(x, y, size: size, bounce: bounce))
        scale.addQuadCurve(
          to: point(x + 0.035, y, size: size, bounce: bounce),
          control: point(x + 0.0175, y + 0.026, size: size, bounce: bounce))
        context.stroke(
          scale,
          with: .color(DragonPalette.paleSilver.opacity(0.48)),
          style: StrokeStyle(
            lineWidth: max(0.34, size.height * 0.0065),
            lineCap: .round))
      }
    }

    let spinePoints: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (0.46, 0.46, 0.47, 0.38),
      (0.52, 0.44, 0.54, 0.35),
      (0.59, 0.45, 0.62, 0.37),
      (0.66, 0.49, 0.71, 0.43),
    ]
    for (baseX, baseY, tipX, tipY) in spinePoints {
      var spine = Path()
      spine.move(to: point(baseX - 0.02, baseY, size: size, bounce: bounce))
      spine.addLine(to: point(tipX, tipY, size: size, bounce: bounce))
      spine.addLine(to: point(baseX + 0.025, baseY + 0.015, size: size, bounce: bounce))
      spine.closeSubpath()
      context.fill(
        spine,
        with: .linearGradient(
          Gradient(colors: [
            DragonPalette.paleSilver,
            DragonPalette.electricBlue.opacity(0.46),
          ]),
          startPoint: point(baseX, baseY, size: size),
          endPoint: point(tipX, tipY, size: size)))
    }
  }

  private func drawEnergyChannels(
    context: inout GraphicsContext,
    size: CGSize,
    bounce: CGFloat,
    pulse: CGFloat
  ) {
    let opacity = 0.5 + Double(pulse) * 0.3
    let lineWidth = max(0.48, size.height * 0.009)

    var neckChannel = Path()
    neckChannel.move(to: point(0.31, 0.31, size: size, bounce: bounce))
    neckChannel.addCurve(
      to: point(0.43, 0.58, size: size, bounce: bounce),
      control1: point(0.33, 0.41, size: size, bounce: bounce),
      control2: point(0.36, 0.5, size: size, bounce: bounce))
    context.stroke(
      neckChannel,
      with: .color(DragonPalette.electricBlue.opacity(opacity)),
      style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

    var bodyChannel = Path()
    bodyChannel.move(to: point(0.43, 0.57, size: size, bounce: bounce))
    bodyChannel.addLine(to: point(0.51, 0.54, size: size, bounce: bounce))
    bodyChannel.addLine(to: point(0.56, 0.63, size: size, bounce: bounce))
    bodyChannel.addLine(to: point(0.65, 0.59, size: size, bounce: bounce))
    context.stroke(
      bodyChannel,
      with: .color(DragonPalette.electricBlue.opacity(opacity * 0.9)),
      style: StrokeStyle(
        lineWidth: lineWidth,
        lineCap: .round,
        lineJoin: .round))
  }

  private func drawSparks(
    context: inout GraphicsContext,
    size: CGSize,
    pulse: CGFloat,
    intensity: CGFloat
  ) {
    let count = max(2, Int(3 + intensity * 5))
    let anchors = [
      point(0.28, 0.02, size: size),
      point(0.18, 0.26, size: size),
      point(0.73, 0.2, size: size),
      point(0.34, 0.88, size: size),
    ]

    for index in 0..<count {
      let anchor = anchors[index % anchors.count]
      let angle = CGFloat(index) * 1.73 + pulse * 0.8
      let radius = size.height * (0.025 + CGFloat(index % 3) * 0.013)
      let start = CGPoint(
        x: anchor.x + cos(angle) * radius,
        y: anchor.y + sin(angle) * radius)
      let end = CGPoint(
        x: start.x + cos(angle + 0.8) * radius * 1.8,
        y: start.y + sin(angle + 0.8) * radius * 1.8)

      var spark = Path()
      spark.move(to: start)
      spark.addLine(to: CGPoint(
        x: (start.x + end.x) / 2 + sin(angle * 2) * radius * 0.7,
        y: (start.y + end.y) / 2 - cos(angle * 2) * radius * 0.7))
      spark.addLine(to: end)
      context.stroke(
        spark,
        with: .color(DragonPalette.electricBlue.opacity(0.34 + Double(intensity) * 0.5)),
        style: StrokeStyle(
          lineWidth: max(0.45, size.height * 0.008),
          lineCap: .round,
          lineJoin: .round))
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
      let jitter = CGFloat(sin(phase * 2 + Double(index) * 1.43)) * 2.4 * envelope
      path.addLine(to: CGPoint(
        x: base.x + normal.x * jitter,
        y: base.y + normal.y * jitter))
    }
    return path
  }
}

private enum DragonPalette {
  static let paleSilver = Color(red: 0.9, green: 0.94, blue: 1)
  static let iceSilver = Color(red: 0.68, green: 0.78, blue: 0.9)
  static let silverBlue = Color(red: 0.31, green: 0.43, blue: 0.6)
  static let graphite = Color(red: 0.09, green: 0.13, blue: 0.22)
  static let deepBlue = Color(red: 0.05, green: 0.13, blue: 0.34)
  static let electricBlue = Color(red: 0.18, green: 0.76, blue: 1)
  static let eyeCore = Color(red: 0.55, green: 0.95, blue: 1)
}
