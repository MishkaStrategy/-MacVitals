import SwiftUI

struct DetailedElectricDragonView: View {
  let activity: StatusBarPetActivity
  let time: TimeInterval
  let sparkIntensity: Double
  let crawlPhase: CGFloat
  let travelVelocity: CGFloat
  let perchBlend: CGFloat

  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      let pose = DragonAnimationPose(
        activity: activity,
        time: time,
        crawlPhase: crawlPhase,
        travelVelocity: travelVelocity,
        perchBlend: perchBlend,
        sparkIntensity: CGFloat(sparkIntensity))

      drawAura(context: &context, size: size, pose: pose)
      drawTail(context: &context, size: size, pose: pose)
      drawRearWing(context: &context, size: size, pose: pose)
      drawRearLeg(context: &context, size: size, pose: pose)
      drawBody(context: &context, size: size, pose: pose)
      drawNeck(context: &context, size: size, pose: pose)
      drawCrest(context: &context, size: size, pose: pose)
      drawHead(context: &context, size: size, pose: pose)
      drawFrontWing(context: &context, size: size, pose: pose)
      drawFrontLegs(context: &context, size: size, pose: pose)
      drawBodyScales(context: &context, size: size, pose: pose)
      drawBellyPlates(context: &context, size: size, pose: pose)
      drawEnergyChannels(context: &context, size: size, pose: pose)
      drawFace(context: &context, size: size, pose: pose)
      drawSparks(context: &context, size: size, pose: pose)
    }
  }

  private func p(
    _ x: CGFloat,
    _ y: CGFloat,
    size: CGSize,
    dx: CGFloat = 0,
    dy: CGFloat = 0
  ) -> CGPoint {
    CGPoint(x: size.width * x + dx, y: size.height * y + dy)
  }

  private func drawAura(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let aura = CGRect(
      x: size.width * 0.03,
      y: size.height * 0.04,
      width: size.width * 0.94,
      height: size.height * 0.88)
    context.fill(
      Path(ellipseIn: aura),
      with: .radialGradient(
        Gradient(colors: [
          DragonColors.electric.opacity(0.055 + Double(pose.charge) * 0.085),
          DragonColors.deepBlue.opacity(0.025),
          .clear,
        ]),
        center: CGPoint(x: aura.midX, y: aura.midY),
        startRadius: 1,
        endRadius: aura.width * 0.58))
  }

  private func drawTail(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let sway = pose.tailSway * size.height * 0.025
    var tail = Path()
    tail.move(to: p(0.42, 0.60, size: size, dy: pose.bodyLift))
    tail.addCurve(
      to: p(0.17, 0.67, size: size, dy: sway),
      control1: p(0.34, 0.57, size: size, dy: pose.bodyLift),
      control2: p(0.23, 0.56, size: size, dy: sway))
    tail.addCurve(
      to: p(0.08, 0.83, size: size, dy: sway * 1.3),
      control1: p(0.08, 0.70, size: size, dy: sway),
      control2: p(0.04, 0.78, size: size, dy: sway * 1.2))
    tail.addCurve(
      to: p(0.25, 0.89, size: size, dy: sway * 0.9),
      control1: p(0.10, 0.91, size: size, dy: sway * 1.2),
      control2: p(0.19, 0.93, size: size, dy: sway))

    let glowWidth = max(4.2, size.height * 0.12)
    let bodyWidth = max(2.7, size.height * 0.078)
    context.stroke(
      tail,
      with: .color(DragonColors.electric.opacity(0.16 + Double(pose.charge) * 0.08)),
      style: StrokeStyle(lineWidth: glowWidth, lineCap: .round, lineJoin: .round))
    context.stroke(
      tail,
      with: .linearGradient(
        Gradient(colors: [
          DragonColors.graphite,
          DragonColors.slate,
          DragonColors.silver,
        ]),
        startPoint: p(0.45, 0.56, size: size),
        endPoint: p(0.08, 0.86, size: size)),
      style: StrokeStyle(lineWidth: bodyWidth, lineCap: .round, lineJoin: .round))

    var channel = Path()
    channel.move(to: p(0.41, 0.59, size: size, dy: pose.bodyLift))
    channel.addCurve(
      to: p(0.10, 0.84, size: size, dy: sway),
      control1: p(0.28, 0.60, size: size, dy: sway * 0.3),
      control2: p(0.02, 0.70, size: size, dy: sway))
    context.stroke(
      channel,
      with: .color(DragonColors.electric.opacity(0.56 + Double(pose.charge) * 0.32)),
      style: StrokeStyle(
        lineWidth: max(0.55, size.height * 0.012),
        lineCap: .round,
        lineJoin: .round))

    drawTailFin(context: &context, size: size, pose: pose, sway: sway)
  }

  private func drawTailFin(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose,
    sway: CGFloat
  ) {
    let root = p(0.10, 0.84, size: size, dy: sway)
    let tips = [
      p(0.015, 0.73, size: size, dy: sway * 1.25),
      p(0.005, 0.84, size: size, dy: sway * 1.15),
      p(0.035, 0.95, size: size, dy: sway * 0.85),
    ]

    for (index, tip) in tips.enumerated() {
      var fin = Path()
      fin.move(to: root)
      fin.addQuadCurve(
        to: tip,
        control: p(
          0.045,
          0.79 + CGFloat(index) * 0.045,
          size: size,
          dy: sway))
      fin.addQuadCurve(
        to: root,
        control: p(
          0.075,
          0.82 + CGFloat(index) * 0.026,
          size: size,
          dy: sway))
      fin.closeSubpath()
      context.fill(
        fin,
        with: .linearGradient(
          Gradient(colors: [
            DragonColors.silver.opacity(0.86),
            DragonColors.electric.opacity(0.62 + Double(pose.charge) * 0.22),
          ]),
          startPoint: root,
          endPoint: tip))
      context.stroke(
        fin,
        with: .color(DragonColors.ice.opacity(0.54)),
        lineWidth: max(0.38, size.height * 0.008))
    }
  }

  private func drawRearWing(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let lift = pose.wingLift * size.height
    let root = p(0.47, 0.49, size: size, dy: pose.bodyLift)
    var wing = Path()
    wing.move(to: root)
    wing.addCurve(
      to: p(0.29, 0.13, size: size, dy: lift),
      control1: p(0.43, 0.34, size: size, dy: lift * 0.3),
      control2: p(0.35, 0.19, size: size, dy: lift * 0.8))
    wing.addCurve(
      to: p(0.10, 0.28, size: size, dy: lift * 0.55),
      control1: p(0.21, 0.12, size: size, dy: lift),
      control2: p(0.13, 0.18, size: size, dy: lift * 0.8))
    wing.addCurve(
      to: p(0.33, 0.57, size: size, dy: pose.bodyLift),
      control1: p(0.13, 0.42, size: size, dy: lift * 0.25),
      control2: p(0.24, 0.51, size: size, dy: pose.bodyLift))
    wing.closeSubpath()

    context.fill(
      wing,
      with: .linearGradient(
        Gradient(colors: [
          DragonColors.deepBlue.opacity(0.82),
          DragonColors.electric.opacity(0.27),
          DragonColors.ice.opacity(0.08),
        ]),
        startPoint: root,
        endPoint: p(0.12, 0.18, size: size)))
    context.stroke(
      wing,
      with: .color(DragonColors.silver.opacity(0.74)),
      style: StrokeStyle(
        lineWidth: max(0.75, size.height * 0.018),
        lineCap: .round,
        lineJoin: .round))

    drawWingVeins(
      context: &context,
      size: size,
      root: root,
      tips: [
        p(0.29, 0.13, size: size, dy: lift),
        p(0.18, 0.19, size: size, dy: lift * 0.8),
        p(0.11, 0.28, size: size, dy: lift * 0.55),
      ],
      opacity: 0.34 + pose.charge * 0.24)
  }

  private func drawFrontWing(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let lift = pose.wingLift * size.height * 1.18
    let root = p(0.52, 0.47, size: size, dy: pose.bodyLift)
    var wing = Path()
    wing.move(to: root)
    wing.addCurve(
      to: p(0.67, 0.12, size: size, dy: lift),
      control1: p(0.55, 0.31, size: size, dy: lift * 0.25),
      control2: p(0.61, 0.18, size: size, dy: lift * 0.78))
    wing.addCurve(
      to: p(0.88, 0.24, size: size, dy: lift * 0.65),
      control1: p(0.77, 0.10, size: size, dy: lift),
      control2: p(0.85, 0.15, size: size, dy: lift * 0.86))
    wing.addCurve(
      to: p(0.61, 0.58, size: size, dy: pose.bodyLift),
      control1: p(0.86, 0.40, size: size, dy: lift * 0.30),
      control2: p(0.72, 0.54, size: size, dy: pose.bodyLift))
    wing.closeSubpath()

    context.fill(
      wing,
      with: .linearGradient(
        Gradient(colors: [
          DragonColors.deepBlue.opacity(0.92),
          DragonColors.electric.opacity(0.36),
          DragonColors.ice.opacity(0.12),
        ]),
        startPoint: root,
        endPoint: p(0.86, 0.17, size: size)))
    context.stroke(
      wing,
      with: .color(DragonColors.ice.opacity(0.82)),
      style: StrokeStyle(
        lineWidth: max(0.85, size.height * 0.02),
        lineCap: .round,
        lineJoin: .round))

    drawWingVeins(
      context: &context,
      size: size,
      root: root,
      tips: [
        p(0.67, 0.12, size: size, dy: lift),
        p(0.78, 0.16, size: size, dy: lift * 0.82),
        p(0.88, 0.24, size: size, dy: lift * 0.65),
      ],
      opacity: 0.43 + pose.charge * 0.34)
  }

  private func drawWingVeins(
    context: inout GraphicsContext,
    size: CGSize,
    root: CGPoint,
    tips: [CGPoint],
    opacity: CGFloat
  ) {
    for (index, tip) in tips.enumerated() {
      var vein = Path()
      vein.move(to: root)
      let direction = CGFloat(index - 1)
      vein.addQuadCurve(
        to: tip,
        control: CGPoint(
          x: (root.x + tip.x) / 2 + direction * size.width * 0.018,
          y: (root.y + tip.y) / 2 - size.height * 0.025))
      context.stroke(
        vein,
        with: .color(DragonColors.electric.opacity(Double(opacity))),
        style: StrokeStyle(
          lineWidth: max(0.45, size.height * 0.010),
          lineCap: .round))
    }
  }

  private func drawRearLeg(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let stride = pose.rearStride * size.width * 0.025
    drawLeg(
      context: &context,
      size: size,
      hip: p(0.42, 0.61, size: size, dy: pose.bodyLift),
      elbow: p(0.38, 0.71, size: size, dx: -stride),
      paw: p(0.40, 0.81, size: size, dx: stride),
      foreground: false,
      grip: pose.grip)
  }

  private func drawBody(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let bodyRect = CGRect(
      x: size.width * 0.31,
      y: size.height * 0.42 + pose.bodyLift,
      width: size.width * 0.39,
      height: size.height * (0.29 + pose.breath * 0.012))
    context.fill(
      Path(ellipseIn: bodyRect),
      with: .radialGradient(
        Gradient(colors: [
          DragonColors.silver,
          DragonColors.slate,
          DragonColors.graphite,
        ]),
        center: CGPoint(x: bodyRect.midX + bodyRect.width * 0.12, y: bodyRect.minY),
        startRadius: 1,
        endRadius: bodyRect.width * 0.72))
    context.stroke(
      Path(ellipseIn: bodyRect),
      with: .color(DragonColors.ice.opacity(0.58)),
      lineWidth: max(0.62, size.height * 0.014))

    let shoulder = CGRect(
      x: size.width * 0.48,
      y: size.height * 0.40 + pose.bodyLift,
      width: size.width * 0.18,
      height: size.height * 0.23)
    context.fill(
      Path(ellipseIn: shoulder),
      with: .linearGradient(
        Gradient(colors: [DragonColors.ice, DragonColors.slate]),
        startPoint: shoulder.origin,
        endPoint: CGPoint(x: shoulder.maxX, y: shoulder.maxY)))
  }

  private func drawNeck(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let neckLift = pose.headNod * size.height * 0.018
    var neck = Path()
    neck.move(to: p(0.57, 0.49, size: size, dy: pose.bodyLift))
    neck.addCurve(
      to: p(0.70, 0.30, size: size, dy: neckLift),
      control1: p(0.59, 0.43, size: size, dy: pose.bodyLift),
      control2: p(0.63, 0.33, size: size, dy: neckLift))

    context.stroke(
      neck,
      with: .color(DragonColors.electric.opacity(0.16 + Double(pose.charge) * 0.08)),
      style: StrokeStyle(
        lineWidth: max(8, size.height * 0.19),
        lineCap: .round,
        lineJoin: .round))
    context.stroke(
      neck,
      with: .linearGradient(
        Gradient(colors: [DragonColors.slate, DragonColors.silver, DragonColors.ice]),
        startPoint: p(0.55, 0.52, size: size),
        endPoint: p(0.72, 0.25, size: size)),
      style: StrokeStyle(
        lineWidth: max(5.5, size.height * 0.13),
        lineCap: .round,
        lineJoin: .round))
  }

  private func drawCrest(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let nod = pose.headNod * size.height * 0.018
    let roots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (0.65, 0.31, 0.55, 0.15),
      (0.69, 0.27, 0.63, 0.08),
      (0.73, 0.25, 0.72, 0.04),
      (0.77, 0.25, 0.81, 0.06),
    ]

    for (index, item) in roots.enumerated() {
      let root = p(item.0, item.1, size: size, dy: nod)
      let tip = p(
        item.2,
        item.3,
        size: size,
        dy: nod + pose.crestFlutter * CGFloat(index + 1) * 0.35)
      var spike = Path()
      spike.move(to: root)
      spike.addQuadCurve(
        to: tip,
        control: CGPoint(
          x: (root.x + tip.x) / 2 - size.width * 0.015,
          y: (root.y + tip.y) / 2))
      spike.addQuadCurve(
        to: CGPoint(x: root.x + size.width * 0.035, y: root.y + size.height * 0.02),
        control: CGPoint(
          x: (root.x + tip.x) / 2 + size.width * 0.018,
          y: (root.y + tip.y) / 2 + size.height * 0.018))
      spike.closeSubpath()
      context.fill(
        spike,
        with: .linearGradient(
          Gradient(colors: [DragonColors.silver, DragonColors.electric]),
          startPoint: root,
          endPoint: tip))
      context.stroke(
        spike,
        with: .color(DragonColors.ice.opacity(0.72)),
        lineWidth: max(0.38, size.height * 0.008))
    }
  }

  private func drawHead(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let nod = pose.headNod * size.height * 0.018
    var head = Path()
    head.move(to: p(0.66, 0.27, size: size, dy: nod))
    head.addCurve(
      to: p(0.83, 0.22, size: size, dy: nod),
      control1: p(0.72, 0.19, size: size, dy: nod),
      control2: p(0.79, 0.18, size: size, dy: nod))
    head.addCurve(
      to: p(0.94, 0.31, size: size, dy: nod),
      control1: p(0.88, 0.23, size: size, dy: nod),
      control2: p(0.94, 0.26, size: size, dy: nod))
    head.addCurve(
      to: p(0.82, 0.39, size: size, dy: nod),
      control1: p(0.94, 0.36, size: size, dy: nod),
      control2: p(0.88, 0.39, size: size, dy: nod))
    head.addCurve(
      to: p(0.66, 0.27, size: size, dy: nod),
      control1: p(0.75, 0.40, size: size, dy: nod),
      control2: p(0.68, 0.34, size: size, dy: nod))
    head.closeSubpath()

    context.fill(
      head,
      with: .linearGradient(
        Gradient(colors: [
          DragonColors.ice,
          DragonColors.silver,
          DragonColors.slate,
        ]),
        startPoint: p(0.69, 0.19, size: size),
        endPoint: p(0.92, 0.39, size: size)))
    context.stroke(
      head,
      with: .color(DragonColors.ice.opacity(0.80)),
      lineWidth: max(0.62, size.height * 0.014))

    var jaw = Path()
    jaw.move(to: p(0.79, 0.35, size: size, dy: nod))
    jaw.addQuadCurve(
      to: p(0.92, 0.32, size: size, dy: nod),
      control: p(0.87, 0.38, size: size, dy: nod))
    context.stroke(
      jaw,
      with: .color(DragonColors.graphite.opacity(0.72)),
      style: StrokeStyle(lineWidth: max(0.45, size.height * 0.010), lineCap: .round))
  }

  private func drawFrontLegs(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let stride = pose.frontStride * size.width * 0.026
    drawLeg(
      context: &context,
      size: size,
      hip: p(0.59, 0.56, size: size, dy: pose.bodyLift),
      elbow: p(0.62, 0.68, size: size, dx: stride),
      paw: p(0.67, 0.80, size: size, dx: -stride),
      foreground: true,
      grip: pose.grip)
    drawLeg(
      context: &context,
      size: size,
      hip: p(0.51, 0.58, size: size, dy: pose.bodyLift),
      elbow: p(0.50, 0.69, size: size, dx: -stride * 0.8),
      paw: p(0.54, 0.81, size: size, dx: stride * 0.75),
      foreground: true,
      grip: pose.grip * 0.92)
  }

  private func drawLeg(
    context: inout GraphicsContext,
    size: CGSize,
    hip: CGPoint,
    elbow: CGPoint,
    paw: CGPoint,
    foreground: Bool,
    grip: CGFloat
  ) {
    var leg = Path()
    leg.move(to: hip)
    leg.addQuadCurve(to: elbow, control: CGPoint(x: elbow.x - size.width * 0.025, y: hip.y))
    leg.addQuadCurve(to: paw, control: CGPoint(x: paw.x - size.width * 0.025, y: elbow.y))

    context.stroke(
      leg,
      with: .linearGradient(
        Gradient(colors: foreground
          ? [DragonColors.silver, DragonColors.ice]
          : [DragonColors.graphite, DragonColors.slate]),
        startPoint: hip,
        endPoint: paw),
      style: StrokeStyle(
        lineWidth: max(foreground ? 2.5 : 2.1, size.height * (foreground ? 0.055 : 0.047)),
        lineCap: .round,
        lineJoin: .round))

    for index in 0..<3 {
      let spread = CGFloat(index - 1) * size.width * 0.018
      var claw = Path()
      claw.move(to: paw)
      claw.addQuadCurve(
        to: CGPoint(
          x: paw.x + size.width * (0.035 + grip * 0.012),
          y: paw.y + size.height * 0.035 + abs(spread) * 0.25),
        control: CGPoint(
          x: paw.x + spread,
          y: paw.y + size.height * 0.024))
      context.stroke(
        claw,
        with: .color(DragonColors.ice.opacity(0.90)),
        style: StrokeStyle(
          lineWidth: max(0.45, size.height * 0.010),
          lineCap: .round))
    }
  }

  private func drawBodyScales(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let rows: [(CGFloat, CGFloat, Int)] = [
      (0.38, 0.49, 5),
      (0.36, 0.56, 6),
      (0.40, 0.63, 5),
    ]

    for (rowIndex, row) in rows.enumerated() {
      for index in 0..<row.2 {
        let x = row.0 + CGFloat(index) * 0.055
        let y = row.1 + CGFloat(rowIndex % 2) * 0.006
        var scale = Path()
        scale.move(to: p(x, y, size: size, dy: pose.bodyLift))
        scale.addLine(to: p(x + 0.026, y + 0.020, size: size, dy: pose.bodyLift))
        scale.addLine(to: p(x, y + 0.047, size: size, dy: pose.bodyLift))
        scale.addLine(to: p(x - 0.026, y + 0.020, size: size, dy: pose.bodyLift))
        scale.closeSubpath()
        context.fill(
          scale,
          with: .linearGradient(
            Gradient(colors: [
              DragonColors.ice.opacity(0.58),
              DragonColors.slate.opacity(0.62),
            ]),
            startPoint: p(x, y, size: size),
            endPoint: p(x, y + 0.05, size: size)))
        context.stroke(
          scale,
          with: .color(DragonColors.electric.opacity(0.13 + Double(pose.charge) * 0.12)),
          lineWidth: max(0.25, size.height * 0.005))
      }
    }
  }

  private func drawBellyPlates(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    for index in 0..<5 {
      let progress = CGFloat(index) / 4
      let center = p(
        0.64 - progress * 0.10,
        0.35 + progress * 0.20,
        size: size,
        dy: pose.bodyLift * progress)
      let plate = CGRect(
        x: center.x - size.width * 0.035,
        y: center.y - size.height * 0.018,
        width: size.width * 0.07,
        height: size.height * 0.044)
      context.fill(
        Path(ellipseIn: plate),
        with: .linearGradient(
          Gradient(colors: [DragonColors.ice.opacity(0.86), DragonColors.slate.opacity(0.68)]),
          startPoint: plate.origin,
          endPoint: CGPoint(x: plate.maxX, y: plate.maxY)))
    }
  }

  private func drawEnergyChannels(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    var dorsal = Path()
    dorsal.move(to: p(0.27, 0.66, size: size, dy: pose.bodyLift))
    dorsal.addCurve(
      to: p(0.73, 0.28, size: size, dy: pose.headNod * size.height * 0.018),
      control1: p(0.43, 0.68, size: size, dy: pose.bodyLift),
      control2: p(0.58, 0.39, size: size, dy: pose.bodyLift * 0.4))
    context.stroke(
      dorsal,
      with: .color(DragonColors.electric.opacity(0.50 + Double(pose.charge) * 0.40)),
      style: StrokeStyle(
        lineWidth: max(0.55, size.height * 0.012),
        lineCap: .round,
        lineJoin: .round))

    let nodes = [
      p(0.35, 0.61, size: size, dy: pose.bodyLift),
      p(0.48, 0.57, size: size, dy: pose.bodyLift),
      p(0.58, 0.47, size: size, dy: pose.bodyLift),
      p(0.66, 0.35, size: size, dy: pose.headNod * size.height * 0.012),
    ]
    for (index, node) in nodes.enumerated() {
      let radius = max(
        0.8,
        size.height * (0.012 + pose.charge * 0.006 + CGFloat(index) * 0.001))
      context.fill(
        Path(ellipseIn: CGRect(
          x: node.x - radius,
          y: node.y - radius,
          width: radius * 2,
          height: radius * 2)),
        with: .color(DragonColors.ice.opacity(0.62 + Double(pose.charge) * 0.28)))
    }
  }

  private func drawFace(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let nod = pose.headNod * size.height * 0.018
    let eyeCenter = p(0.82, 0.275, size: size, dy: nod)
    let eyeWidth = max(2.3, size.width * 0.048)
    let eyeHeight = max(0.65, size.height * 0.038 * (1 - pose.blink * 0.88))
    let eyeRect = CGRect(
      x: eyeCenter.x - eyeWidth / 2,
      y: eyeCenter.y - eyeHeight / 2,
      width: eyeWidth,
      height: eyeHeight)
    context.fill(
      Path(ellipseIn: eyeRect),
      with: .color(DragonColors.eye.opacity(0.92)))
    context.stroke(
      Path(ellipseIn: eyeRect.insetBy(dx: -0.8, dy: -0.8)),
      with: .color(DragonColors.electric.opacity(0.34 + Double(pose.charge) * 0.36)),
      lineWidth: max(0.35, size.height * 0.007))

    let pupilWidth = max(0.4, eyeWidth * 0.16)
    let pupil = CGRect(
      x: eyeCenter.x + eyeWidth * 0.13,
      y: eyeCenter.y - eyeHeight * 0.45,
      width: pupilWidth,
      height: max(0.6, eyeHeight * 0.9))
    context.fill(Path(ellipseIn: pupil), with: .color(DragonColors.deepBlue))

    let nostril = CGRect(
      x: size.width * 0.895,
      y: size.height * 0.292 + nod,
      width: max(0.8, size.width * 0.012),
      height: max(0.55, size.height * 0.008))
    context.fill(Path(ellipseIn: nostril), with: .color(DragonColors.graphite.opacity(0.92)))
  }

  private func drawSparks(
    context: inout GraphicsContext,
    size: CGSize,
    pose: DragonAnimationPose
  ) {
    let intensity = max(0, pose.sparkIntensity)
    guard intensity > 0.02 else { return }

    let origins = [
      p(0.72, 0.09, size: size),
      p(0.87, 0.21, size: size),
      p(0.08, 0.84, size: size, dy: pose.tailSway * size.height * 0.025),
      p(0.49, 0.54, size: size, dy: pose.bodyLift),
    ]

    for (index, origin) in origins.enumerated() {
      let phase = pose.sparkPhase + CGFloat(index) * 1.7
      let reach = size.height * (0.035 + intensity * 0.05)
      var arc = Path()
      arc.move(to: origin)
      for segment in 1...3 {
        let progress = CGFloat(segment) / 3
        arc.addLine(to: CGPoint(
          x: origin.x + cos(phase + progress * 2.2) * reach * progress,
          y: origin.y + sin(phase * 1.3 + progress * 2.8) * reach * progress))
      }
      context.stroke(
        arc,
        with: .color(DragonColors.electric.opacity(0.30 + Double(intensity) * 0.52)),
        style: StrokeStyle(
          lineWidth: max(0.45, size.height * 0.010),
          lineCap: .round,
          lineJoin: .round))
    }
  }
}

private struct DragonAnimationPose {
  let breath: CGFloat
  let bodyLift: CGFloat
  let headNod: CGFloat
  let frontStride: CGFloat
  let rearStride: CGFloat
  let wingLift: CGFloat
  let tailSway: CGFloat
  let crestFlutter: CGFloat
  let grip: CGFloat
  let blink: CGFloat
  let charge: CGFloat
  let sparkPhase: CGFloat
  let sparkIntensity: CGFloat

  init(
    activity: StatusBarPetActivity,
    time: TimeInterval,
    crawlPhase: CGFloat,
    travelVelocity: CGFloat,
    perchBlend: CGFloat,
    sparkIntensity: CGFloat
  ) {
    let cycle = crawlPhase * .pi * 2
    let movement = min(max(travelVelocity, 0), 1)
    let idle = min(max(perchBlend, 0), 1)
    let breathWave = CGFloat(sin(time * 1.65))
    let chargeWave = CGFloat((sin(time * 4.3) + 1) / 2)

    breath = breathWave * (0.45 + idle * 0.55)
    bodyLift = -abs(CGFloat(sin(Double(cycle)))) * movement * 0.75
    headNod = CGFloat(sin(Double(cycle) + 0.45)) * movement * 0.65
      + breathWave * idle * 0.25
    frontStride = CGFloat(sin(Double(cycle))) * movement
    rearStride = CGFloat(sin(Double(cycle) + .pi)) * movement

    switch activity {
    case .idle:
      wingLift = 0.004 + CGFloat(sin(time * 1.35)) * 0.006
    case .roaming:
      wingLift = 0.012 + abs(CGFloat(sin(Double(cycle)))) * 0.026
    case .playing:
      wingLift = 0.045 + CGFloat((sin(time * 7.5) + 1) / 2) * 0.025
    }

    tailSway = CGFloat(sin(time * (activity == .idle ? 1.15 : 3.8) + Double(cycle) * 0.7))
      * (0.35 + movement * 0.65)
    crestFlutter = CGFloat(sin(time * 4.7 + Double(cycle))) * (0.35 + movement * 0.65)
    grip = 0.55 + idle * 0.45
    blink = CGFloat(pow(max(0, sin(time * 0.71 - 1.1)), 18))
    charge = min(max(chargeWave * 0.58 + movement * 0.25 + (activity == .playing ? 0.28 : 0), 0), 1)
    sparkPhase = CGFloat(time * 4.1) + cycle
    self.sparkIntensity = min(max(sparkIntensity, 0), 1)
  }
}

private enum DragonColors {
  static let graphite = Color(red: 0.10, green: 0.14, blue: 0.22)
  static let slate = Color(red: 0.30, green: 0.39, blue: 0.54)
  static let silver = Color(red: 0.70, green: 0.80, blue: 0.91)
  static let ice = Color(red: 0.88, green: 0.96, blue: 1.0)
  static let deepBlue = Color(red: 0.05, green: 0.12, blue: 0.28)
  static let electric = Color(red: 0.22, green: 0.72, blue: 1.0)
  static let eye = Color(red: 0.58, green: 0.94, blue: 1.0)
}
