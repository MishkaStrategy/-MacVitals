import SwiftUI

/// Procedural 2.5D renderer for the approved silver-blue electric dragon.
///
/// The model intentionally avoids raster assets. Its silhouette and materials are built from
/// layered vector geometry so the pet remains sharp at every supported size.
struct DetailedElectricDragonView: View {
  let activity: StatusBarPetActivity
  let time: TimeInterval
  let sparkIntensity: Double
  let crawlPhase: CGFloat
  let travelVelocity: CGFloat
  let perchBlend: CGFloat

  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
      let pose = ElectrumDragonPose(
        activity: activity,
        time: time,
        crawlPhase: crawlPhase,
        travelVelocity: travelVelocity,
        perchBlend: perchBlend,
        sparkIntensity: CGFloat(sparkIntensity))
      let art = ElectrumDragonArtboard(size: size, pose: pose)

      drawAtmosphericGlow(context: &context, art: art)
      drawContactShadow(context: &context, art: art)
      drawTail(context: &context, art: art)
      drawFarWing(context: &context, art: art)
      drawFarLegs(context: &context, art: art)
      drawTorso(context: &context, art: art)
      drawDorsalArmor(context: &context, art: art)
      drawNearWing(context: &context, art: art)
      drawNeck(context: &context, art: art)
      drawChestPlates(context: &context, art: art)
      drawHead(context: &context, art: art)
      drawCrownAndHorns(context: &context, art: art)
      drawCheekFins(context: &context, art: art)
      drawNearLegs(context: &context, art: art)
      drawTorsoScales(context: &context, art: art)
      drawSpecularAccents(context: &context, art: art)
      drawElectricChannels(context: &context, art: art)
      drawFace(context: &context, art: art)
      drawFreeArcs(context: &context, art: art)
    }
  }

  private func drawAtmosphericGlow(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let rect = CGRect(
      x: art.size.width * 0.015,
      y: art.size.height * 0.01,
      width: art.size.width * 0.97,
      height: art.size.height * 0.96)
    context.fill(
      Path(ellipseIn: rect),
      with: .radialGradient(
        Gradient(colors: [
          ElectrumPalette.electric.opacity(0.055 + Double(art.pose.charge) * 0.08),
          ElectrumPalette.deepBlue.opacity(0.025),
          .clear,
        ]),
        center: CGPoint(x: rect.midX, y: rect.midY * 0.92),
        startRadius: 1,
        endRadius: rect.width * 0.55))
  }

  private func drawContactShadow(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let shadow = CGRect(
      x: art.size.width * 0.26,
      y: art.size.height * (0.735 + art.pose.bodyLift),
      width: art.size.width * 0.52,
      height: max(1.4, art.size.height * 0.055))
    context.fill(
      Path(ellipseIn: shadow),
      with: .radialGradient(
        Gradient(colors: [
          Color.black.opacity(0.48),
          ElectrumPalette.electric.opacity(0.06),
          .clear,
        ]),
        center: CGPoint(x: shadow.midX, y: shadow.midY),
        startRadius: 0,
        endRadius: shadow.width * 0.5))
  }

  // MARK: - Tail

  private func drawTail(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let p0 = art.point(0.37, 0.56, dy: art.pose.bodyLift)
    let p1 = art.point(
      0.25 - art.pose.stretch * 0.035,
      0.63 + art.pose.tailHang * 0.035,
      dy: art.pose.tailSway * art.size.height * 0.012)
    let p2 = art.point(
      0.18 + art.pose.tailSway * 0.018,
      0.78 + art.pose.tailHang * 0.09,
      dy: art.pose.tailSway * art.size.height * 0.018)
    let p3 = art.point(
      0.31 + art.pose.tailSway * 0.028,
      0.91,
      dy: art.pose.tailSway * art.size.height * 0.02)

    let tail = taperedRibbon(
      points: [p0, p1, p2, p3],
      startWidth: art.size.height * 0.105,
      endWidth: art.size.height * 0.036)

    context.fill(
      tail,
      with: .linearGradient(
        Gradient(colors: [
          ElectrumPalette.graphite,
          ElectrumPalette.steel,
          ElectrumPalette.silver,
        ]),
        startPoint: p0,
        endPoint: p3))
    context.stroke(
      tail,
      with: .color(ElectrumPalette.ice.opacity(0.50)),
      lineWidth: art.hairline * 1.1)

    drawTailScutes(context: &context, art: art, points: [p0, p1, p2, p3])
    drawTailFin(context: &context, art: art, root: p3)
  }

  private func drawTailScutes(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard,
    points: [CGPoint]
  ) {
    for index in 1...8 {
      let t = CGFloat(index) / 9
      let center = cubicPoint(points: points, t: t)
      let tangent = cubicTangent(points: points, t: t)
      let normal = normalized(CGPoint(x: -tangent.y, y: tangent.x))
      let half = art.size.height * (0.035 - t * 0.018)
      let length = art.size.width * (0.026 - t * 0.008)
      let forward = normalized(tangent)

      var plate = Path()
      plate.move(to: offset(center, normal, half))
      plate.addLine(to: offset(offset(center, forward, length), normal, half * 0.25))
      plate.addLine(to: offset(center, normal, -half))
      plate.addLine(to: offset(offset(center, forward, -length * 0.6), normal, -half * 0.2))
      plate.closeSubpath()

      context.fill(
        plate,
        with: .linearGradient(
          Gradient(colors: [
            ElectrumPalette.ice.opacity(0.78),
            ElectrumPalette.slate.opacity(0.72),
          ]),
          startPoint: offset(center, normal, half),
          endPoint: offset(center, normal, -half)))
      context.stroke(
        plate,
        with: .color(ElectrumPalette.electric.opacity(0.16 + Double(art.pose.charge) * 0.18)),
        lineWidth: art.hairline * 0.65)
    }
  }

  private func drawTailFin(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard,
    root: CGPoint
  ) {
    let sway = art.pose.tailSway
    let fins = [
      art.point(0.20 + sway * 0.025, 0.79),
      art.point(0.18 + sway * 0.035, 0.88),
      art.point(0.23 + sway * 0.045, 0.985),
      art.point(0.34 + sway * 0.055, 0.965),
    ]

    for (index, tip) in fins.enumerated() {
      var fin = Path()
      fin.move(to: root)
      let bias = CGFloat(index) - 1.5
      fin.addQuadCurve(
        to: tip,
        control: CGPoint(
          x: (root.x + tip.x) * 0.5 + bias * art.size.width * 0.008,
          y: (root.y + tip.y) * 0.5 - art.size.height * 0.018))
      fin.addQuadCurve(
        to: root,
        control: CGPoint(
          x: (root.x + tip.x) * 0.5 + art.size.width * 0.025,
          y: (root.y + tip.y) * 0.5 + art.size.height * 0.022))
      fin.closeSubpath()

      context.fill(
        fin,
        with: .linearGradient(
          Gradient(colors: [
            ElectrumPalette.silver.opacity(0.95),
            ElectrumPalette.electric.opacity(0.66 + Double(art.pose.charge) * 0.25),
            ElectrumPalette.deepBlue.opacity(0.82),
          ]),
          startPoint: root,
          endPoint: tip))
      context.stroke(
        fin,
        with: .color(ElectrumPalette.ice.opacity(0.76)),
        lineWidth: art.hairline)
    }
  }

  // MARK: - Wings

  private func drawFarWing(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    drawWing(
      context: &context,
      art: art,
      root: art.point(0.43, 0.43, dy: art.pose.bodyLift),
      leading: art.point(0.27, 0.11 - art.pose.wingOpen * 0.018),
      outer: art.point(0.075, 0.20 + art.pose.wingFold * 0.06),
      trailing: art.point(0.20, 0.53 + art.pose.wingFold * 0.05),
      foreground: false)
  }

  private func drawNearWing(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    drawWing(
      context: &context,
      art: art,
      root: art.point(0.53, 0.42, dy: art.pose.bodyLift),
      leading: art.point(0.67, 0.085 - art.pose.wingOpen * 0.025),
      outer: art.point(0.96, 0.17 + art.pose.wingFold * 0.055),
      trailing: art.point(0.77, 0.56 + art.pose.wingFold * 0.05),
      foreground: true)
  }

  private func drawWing(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard,
    root: CGPoint,
    leading: CGPoint,
    outer: CGPoint,
    trailing: CGPoint,
    foreground: Bool
  ) {
    let flutter = art.pose.wingFlutter * art.size.height * (foreground ? 0.012 : 0.008)
    let foldedTrailing = CGPoint(x: trailing.x, y: trailing.y + flutter)
    let finger1 = interpolate(leading, outer, 0.35)
    let finger2 = interpolate(leading, outer, 0.62)
    let finger3 = interpolate(leading, outer, 0.84)

    var membrane = Path()
    membrane.move(to: root)
    membrane.addCurve(
      to: leading,
      control1: CGPoint(x: root.x + (leading.x - root.x) * 0.22, y: root.y - art.size.height * 0.16),
      control2: CGPoint(x: leading.x, y: leading.y + art.size.height * 0.04))
    membrane.addCurve(
      to: outer,
      control1: CGPoint(x: finger1.x, y: finger1.y - art.size.height * 0.025),
      control2: CGPoint(x: finger3.x, y: finger3.y - art.size.height * 0.015))
    membrane.addLine(to: foldedTrailing)
    membrane.addQuadCurve(
      to: CGPoint(x: root.x + (trailing.x - root.x) * 0.52, y: trailing.y - art.size.height * 0.015),
      control: CGPoint(x: trailing.x - art.size.width * 0.03, y: trailing.y + art.size.height * 0.045))
    membrane.addQuadCurve(
      to: root,
      control: CGPoint(x: root.x + (trailing.x - root.x) * 0.20, y: root.y + art.size.height * 0.085))
    membrane.closeSubpath()

    context.fill(
      membrane,
      with: .linearGradient(
        Gradient(colors: foreground
          ? [
            ElectrumPalette.deepBlue.opacity(0.96),
            ElectrumPalette.cobalt.opacity(0.72),
            ElectrumPalette.electric.opacity(0.22),
            ElectrumPalette.ice.opacity(0.08),
          ]
          : [
            ElectrumPalette.deepBlue.opacity(0.78),
            ElectrumPalette.cobalt.opacity(0.52),
            ElectrumPalette.electric.opacity(0.14),
          ]),
        startPoint: root,
        endPoint: outer))
    context.stroke(
      membrane,
      with: .color((foreground ? ElectrumPalette.ice : ElectrumPalette.silver).opacity(foreground ? 0.86 : 0.56)),
      style: StrokeStyle(
        lineWidth: art.hairline * (foreground ? 1.55 : 1.15),
        lineCap: .round,
        lineJoin: .round))

    let fingers = [leading, finger1, finger2, finger3, outer]
    for (index, tip) in fingers.enumerated() {
      var bone = Path()
      bone.move(to: root)
      bone.addQuadCurve(
        to: tip,
        control: CGPoint(
          x: (root.x + tip.x) * 0.5,
          y: (root.y + tip.y) * 0.5 - art.size.height * (0.035 + CGFloat(index) * 0.004)))
      context.stroke(
        bone,
        with: .linearGradient(
          Gradient(colors: [ElectrumPalette.steel, ElectrumPalette.ice]),
          startPoint: root,
          endPoint: tip),
        style: StrokeStyle(
          lineWidth: art.hairline * (foreground ? 1.25 : 0.9),
          lineCap: .round,
          lineJoin: .round))
    }

    drawWingElectricVeins(
      context: &context,
      art: art,
      root: root,
      outer: outer,
      trailing: foldedTrailing,
      foreground: foreground)
  }

  private func drawWingElectricVeins(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard,
    root: CGPoint,
    outer: CGPoint,
    trailing: CGPoint,
    foreground: Bool
  ) {
    let opacity = Double(0.34 + art.pose.charge * (foreground ? 0.42 : 0.28))
    for index in 0..<4 {
      let t = CGFloat(index + 1) / 5
      let start = interpolate(root, outer, t * 0.72)
      let end = interpolate(root, trailing, 0.42 + t * 0.42)
      var vein = Path()
      vein.move(to: start)
      vein.addLine(to: CGPoint(
        x: interpolate(start, end, 0.38).x + art.size.width * (index.isMultiple(of: 2) ? 0.012 : -0.009),
        y: interpolate(start, end, 0.38).y - art.size.height * 0.008))
      vein.addLine(to: CGPoint(
        x: interpolate(start, end, 0.68).x + art.size.width * (index.isMultiple(of: 2) ? -0.008 : 0.011),
        y: interpolate(start, end, 0.68).y + art.size.height * 0.006))
      vein.addLine(to: end)
      context.stroke(
        vein,
        with: .color(ElectrumPalette.electric.opacity(opacity)),
        style: StrokeStyle(
          lineWidth: art.hairline * 0.72,
          lineCap: .round,
          lineJoin: .round))
    }
  }

  // MARK: - Torso and armor

  private func drawTorso(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let lift = art.pose.bodyLift
    let stretch = art.pose.stretch
    var body = Path()
    body.move(to: art.point(0.29 - stretch * 0.025, 0.51, dy: lift))
    body.addCurve(
      to: art.point(0.54 + stretch * 0.025, 0.40, dy: lift),
      control1: art.point(0.34, 0.41, dy: lift),
      control2: art.point(0.46, 0.37, dy: lift))
    body.addCurve(
      to: art.point(0.72 + stretch * 0.035, 0.52, dy: lift),
      control1: art.point(0.64, 0.40, dy: lift),
      control2: art.point(0.71, 0.44, dy: lift))
    body.addCurve(
      to: art.point(0.57, 0.68, dy: lift),
      control1: art.point(0.72, 0.61, dy: lift),
      control2: art.point(0.66, 0.68, dy: lift))
    body.addCurve(
      to: art.point(0.29 - stretch * 0.025, 0.51, dy: lift),
      control1: art.point(0.45, 0.71, dy: lift),
      control2: art.point(0.34, 0.63, dy: lift))
    body.closeSubpath()

    context.fill(
      body,
      with: .radialGradient(
        Gradient(colors: [
          ElectrumPalette.ice,
          ElectrumPalette.silver,
          ElectrumPalette.steel,
          ElectrumPalette.graphite,
        ]),
        center: art.point(0.51, 0.39, dy: lift),
        startRadius: 1,
        endRadius: art.size.width * 0.32))
    context.stroke(
      body,
      with: .color(ElectrumPalette.ice.opacity(0.60)),
      lineWidth: art.hairline * 1.25)

    var belly = Path()
    belly.move(to: art.point(0.33, 0.57, dy: lift))
    belly.addCurve(
      to: art.point(0.61, 0.64, dy: lift),
      control1: art.point(0.42, 0.68, dy: lift),
      control2: art.point(0.54, 0.70, dy: lift))
    context.stroke(
      belly,
      with: .color(ElectrumPalette.deepBlue.opacity(0.45)),
      style: StrokeStyle(
        lineWidth: art.hairline * 1.4,
        lineCap: .round))
  }

  private func drawDorsalArmor(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    for index in 0..<7 {
      let t = CGFloat(index) / 6
      let x = 0.31 + t * 0.38
      let baseY = 0.43 - sin(t * .pi) * 0.055 + art.pose.bodyLift
      let height = 0.055 + sin(t * .pi) * 0.035
      let root = art.point(x, baseY)
      let tip = art.point(
        x - 0.025 + art.pose.crestFlutter * 0.003 * CGFloat(index),
        baseY - height)
      let rear = art.point(x + 0.038, baseY + 0.014)
      var spike = Path()
      spike.move(to: root)
      spike.addQuadCurve(
        to: tip,
        control: art.point(x - 0.010, baseY - height * 0.6))
      spike.addQuadCurve(
        to: rear,
        control: art.point(x + 0.020, baseY - height * 0.28))
      spike.closeSubpath()
      context.fill(
        spike,
        with: .linearGradient(
          Gradient(colors: [ElectrumPalette.steel, ElectrumPalette.ice]),
          startPoint: rear,
          endPoint: tip))
      context.stroke(
        spike,
        with: .color(ElectrumPalette.electric.opacity(0.18 + Double(art.pose.charge) * 0.18)),
        lineWidth: art.hairline * 0.65)
    }
  }

  private func drawTorsoScales(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let rows: [(CGFloat, CGFloat, Int, CGFloat)] = [
      (0.36, 0.47, 6, 0.050),
      (0.34, 0.53, 7, 0.048),
      (0.37, 0.59, 6, 0.050),
    ]

    for (rowIndex, row) in rows.enumerated() {
      for index in 0..<row.2 {
        let x = row.0 + CGFloat(index) * row.3
        let y = row.1 + CGFloat(rowIndex % 2) * 0.003 + art.pose.bodyLift
        let halfW = art.size.width * 0.021
        let halfH = art.size.height * 0.027
        let center = art.point(x, y)
        var scale = Path()
        scale.move(to: CGPoint(x: center.x, y: center.y - halfH))
        scale.addLine(to: CGPoint(x: center.x + halfW, y: center.y))
        scale.addLine(to: CGPoint(x: center.x, y: center.y + halfH))
        scale.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
        scale.closeSubpath()
        context.fill(
          scale,
          with: .linearGradient(
            Gradient(colors: [
              ElectrumPalette.ice.opacity(0.76),
              ElectrumPalette.silver.opacity(0.72),
              ElectrumPalette.slate.opacity(0.70),
            ]),
            startPoint: CGPoint(x: center.x, y: center.y - halfH),
            endPoint: CGPoint(x: center.x, y: center.y + halfH)))
        context.stroke(
          scale,
          with: .color(ElectrumPalette.deepBlue.opacity(0.44)),
          lineWidth: art.hairline * 0.55)
      }
    }
  }

  // MARK: - Neck and head

  private func drawNeck(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let start = art.point(0.57, 0.47, dy: art.pose.bodyLift)
    let mid = art.point(
      0.61 + art.pose.stretch * 0.025,
      0.34 + art.pose.stretch * 0.035,
      dy: art.pose.headNod * art.size.height * 0.018)
    let end = art.point(
      0.70 + art.pose.stretch * 0.045,
      0.26 + art.pose.stretch * 0.045,
      dy: art.pose.headNod * art.size.height * 0.024)

    var neck = Path()
    neck.move(to: start)
    neck.addCurve(
      to: end,
      control1: CGPoint(x: start.x + art.size.width * 0.015, y: start.y - art.size.height * 0.12),
      control2: CGPoint(x: mid.x - art.size.width * 0.035, y: mid.y - art.size.height * 0.055))

    context.stroke(
      neck,
      with: .color(ElectrumPalette.electric.opacity(0.11 + Double(art.pose.charge) * 0.08)),
      style: StrokeStyle(
        lineWidth: art.size.height * 0.19,
        lineCap: .round,
        lineJoin: .round))
    context.stroke(
      neck,
      with: .linearGradient(
        Gradient(colors: [
          ElectrumPalette.graphite,
          ElectrumPalette.steel,
          ElectrumPalette.silver,
          ElectrumPalette.ice,
        ]),
        startPoint: start,
        endPoint: end),
      style: StrokeStyle(
        lineWidth: art.size.height * 0.132,
        lineCap: .round,
        lineJoin: .round))
  }

  private func drawChestPlates(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    for index in 0..<7 {
      let t = CGFloat(index) / 6
      let center = art.point(
        0.595 + t * 0.09 + art.pose.stretch * 0.035 * t,
        0.46 - t * 0.21 + art.pose.bodyLift * (1 - t),
        dy: art.pose.headNod * art.size.height * 0.018 * t)
      let width = art.size.width * (0.080 - t * 0.018)
      let height = art.size.height * 0.048
      var plate = Path()
      plate.move(to: CGPoint(x: center.x - width * 0.48, y: center.y - height * 0.38))
      plate.addQuadCurve(
        to: CGPoint(x: center.x + width * 0.48, y: center.y - height * 0.28),
        control: CGPoint(x: center.x, y: center.y - height * 0.72))
      plate.addQuadCurve(
        to: CGPoint(x: center.x, y: center.y + height * 0.58),
        control: CGPoint(x: center.x + width * 0.42, y: center.y + height * 0.26))
      plate.addQuadCurve(
        to: CGPoint(x: center.x - width * 0.48, y: center.y - height * 0.38),
        control: CGPoint(x: center.x - width * 0.40, y: center.y + height * 0.20))
      plate.closeSubpath()
      context.fill(
        plate,
        with: .linearGradient(
          Gradient(colors: [ElectrumPalette.ice, ElectrumPalette.silver, ElectrumPalette.slate]),
          startPoint: CGPoint(x: center.x - width * 0.4, y: center.y - height * 0.5),
          endPoint: CGPoint(x: center.x + width * 0.4, y: center.y + height * 0.5)))
      context.stroke(
        plate,
        with: .color(ElectrumPalette.cobalt.opacity(0.48)),
        lineWidth: art.hairline * 0.55)
    }
  }

  private func drawHead(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let dx = art.pose.stretch * 0.055
    let dy = art.pose.headNod * 0.018 + art.pose.stretch * 0.035
    var head = Path()
    head.move(to: art.point(0.655 + dx, 0.245 + dy))
    head.addCurve(
      to: art.point(0.78 + dx, 0.175 + dy),
      control1: art.point(0.69 + dx, 0.185 + dy),
      control2: art.point(0.74 + dx, 0.165 + dy))
    head.addLine(to: art.point(0.90 + dx, 0.235 + dy))
    head.addLine(to: art.point(0.955 + dx, 0.295 + dy))
    head.addQuadCurve(
      to: art.point(0.865 + dx, 0.355 + dy),
      control: art.point(0.935 + dx, 0.355 + dy))
    head.addLine(to: art.point(0.755 + dx, 0.345 + dy))
    head.addQuadCurve(
      to: art.point(0.655 + dx, 0.245 + dy),
      control: art.point(0.685 + dx, 0.335 + dy))
    head.closeSubpath()

    context.fill(
      head,
      with: .linearGradient(
        Gradient(colors: [
          ElectrumPalette.ice,
          ElectrumPalette.silver,
          ElectrumPalette.steel,
          ElectrumPalette.graphite,
        ]),
        startPoint: art.point(0.70 + dx, 0.17 + dy),
        endPoint: art.point(0.94 + dx, 0.36 + dy)))
    context.stroke(
      head,
      with: .color(ElectrumPalette.ice.opacity(0.82)),
      lineWidth: art.hairline * 1.25)

    var brow = Path()
    brow.move(to: art.point(0.73 + dx, 0.235 + dy))
    brow.addLine(to: art.point(0.845 + dx, 0.215 + dy))
    brow.addLine(to: art.point(0.885 + dx, 0.25 + dy))
    context.stroke(
      brow,
      with: .color(ElectrumPalette.graphite.opacity(0.75)),
      style: StrokeStyle(
        lineWidth: art.hairline * 1.2,
        lineCap: .round,
        lineJoin: .round))

    var jaw = Path()
    jaw.move(to: art.point(0.77 + dx, 0.325 + dy))
    jaw.addCurve(
      to: art.point(0.945 + dx, 0.30 + dy),
      control1: art.point(0.84 + dx, 0.37 + dy),
      control2: art.point(0.91 + dx, 0.34 + dy))
    context.stroke(
      jaw,
      with: .color(ElectrumPalette.deepBlue.opacity(0.75)),
      style: StrokeStyle(lineWidth: art.hairline * 0.85, lineCap: .round))
  }

  private func drawCrownAndHorns(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let dx = art.pose.stretch * 0.055
    let dy = art.pose.headNod * 0.018 + art.pose.stretch * 0.035
    let horns: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (0.70, 0.235, 0.49, 0.055, 1.00),
      (0.735, 0.205, 0.56, 0.015, 0.92),
      (0.775, 0.185, 0.67, 0.005, 0.82),
      (0.815, 0.19, 0.79, 0.035, 0.68),
    ]

    for (index, horn) in horns.enumerated() {
      let root = art.point(horn.0 + dx, horn.1 + dy)
      let flutter = art.pose.crestFlutter * 0.003 * CGFloat(index + 1)
      let tip = art.point(horn.2 + dx, horn.3 + dy + flutter)
      let rear = art.point(horn.0 + dx + 0.040 * horn.4, horn.1 + dy + 0.032)
      var spike = Path()
      spike.move(to: root)
      spike.addCurve(
        to: tip,
        control1: CGPoint(x: root.x - art.size.width * 0.045, y: root.y - art.size.height * 0.06),
        control2: CGPoint(x: tip.x + art.size.width * 0.035, y: tip.y + art.size.height * 0.015))
      spike.addCurve(
        to: rear,
        control1: CGPoint(x: tip.x + art.size.width * 0.06, y: tip.y + art.size.height * 0.05),
        control2: CGPoint(x: rear.x - art.size.width * 0.02, y: rear.y - art.size.height * 0.035))
      spike.closeSubpath()
      context.fill(
        spike,
        with: .linearGradient(
          Gradient(colors: [
            ElectrumPalette.steel,
            ElectrumPalette.ice,
            ElectrumPalette.electric,
          ]),
          startPoint: rear,
          endPoint: tip))
      context.stroke(
        spike,
        with: .color(ElectrumPalette.ice.opacity(0.76)),
        lineWidth: art.hairline * 0.8)
    }

    for index in 0..<5 {
      let t = CGFloat(index) / 4
      let root = art.point(0.66 + dx + t * 0.10, 0.285 + dy - t * 0.055)
      let tip = art.point(0.59 + dx + t * 0.10, 0.22 + dy - t * 0.045)
      let rear = art.point(0.69 + dx + t * 0.10, 0.305 + dy - t * 0.050)
      var crown = Path()
      crown.move(to: root)
      crown.addLine(to: tip)
      crown.addLine(to: rear)
      crown.closeSubpath()
      context.fill(
        crown,
        with: .linearGradient(
          Gradient(colors: [ElectrumPalette.silver, ElectrumPalette.ice]),
          startPoint: rear,
          endPoint: tip))
    }
  }

  private func drawCheekFins(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let dx = art.pose.stretch * 0.055
    let dy = art.pose.headNod * 0.018 + art.pose.stretch * 0.035
    let roots = [
      art.point(0.71 + dx, 0.30 + dy),
      art.point(0.73 + dx, 0.33 + dy),
      art.point(0.76 + dx, 0.35 + dy),
    ]
    for (index, root) in roots.enumerated() {
      let tip = art.point(
        0.62 + dx + CGFloat(index) * 0.025,
        0.34 + dy + CGFloat(index) * 0.035)
      var fin = Path()
      fin.move(to: root)
      fin.addLine(to: tip)
      fin.addLine(to: CGPoint(x: root.x + art.size.width * 0.035, y: root.y + art.size.height * 0.025))
      fin.closeSubpath()
      context.fill(
        fin,
        with: .linearGradient(
          Gradient(colors: [ElectrumPalette.ice, ElectrumPalette.cobalt]),
          startPoint: root,
          endPoint: tip))
      context.stroke(
        fin,
        with: .color(ElectrumPalette.electric.opacity(0.34)),
        lineWidth: art.hairline * 0.55)
    }
  }

  // MARK: - Legs and claws

  private func drawFarLegs(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    drawArmoredLeg(
      context: &context,
      art: art,
      hip: art.point(0.40, 0.57, dy: art.pose.bodyLift),
      elbow: art.point(0.34 - art.pose.rearStride * 0.018, 0.68),
      wrist: art.point(0.36 + art.pose.rearStride * 0.018, 0.77),
      foreground: false,
      clawDirection: 1)
    drawArmoredLeg(
      context: &context,
      art: art,
      hip: art.point(0.58, 0.56, dy: art.pose.bodyLift),
      elbow: art.point(0.61 + art.pose.frontStride * 0.016, 0.67),
      wrist: art.point(0.65 - art.pose.frontStride * 0.016, 0.76),
      foreground: false,
      clawDirection: 1)
  }

  private func drawNearLegs(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    drawArmoredLeg(
      context: &context,
      art: art,
      hip: art.point(0.52, 0.55, dy: art.pose.bodyLift),
      elbow: art.point(0.50 - art.pose.frontStride * 0.020, 0.68),
      wrist: art.point(0.53 + art.pose.frontStride * 0.022, 0.78),
      foreground: true,
      clawDirection: 1)
    drawArmoredLeg(
      context: &context,
      art: art,
      hip: art.point(0.67, 0.51, dy: art.pose.bodyLift),
      elbow: art.point(0.70 + art.pose.rearStride * 0.018, 0.65),
      wrist: art.point(0.73 - art.pose.rearStride * 0.020, 0.77),
      foreground: true,
      clawDirection: 1)
  }

  private func drawArmoredLeg(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard,
    hip: CGPoint,
    elbow: CGPoint,
    wrist: CGPoint,
    foreground: Bool,
    clawDirection: CGFloat
  ) {
    var limb = Path()
    limb.move(to: hip)
    limb.addQuadCurve(
      to: elbow,
      control: CGPoint(x: elbow.x - art.size.width * 0.018, y: hip.y + art.size.height * 0.025))
    limb.addQuadCurve(
      to: wrist,
      control: CGPoint(x: wrist.x - art.size.width * 0.022, y: elbow.y + art.size.height * 0.025))
    context.stroke(
      limb,
      with: .linearGradient(
        Gradient(colors: foreground
          ? [ElectrumPalette.silver, ElectrumPalette.ice, ElectrumPalette.steel]
          : [ElectrumPalette.graphite, ElectrumPalette.slate, ElectrumPalette.silver]),
        startPoint: hip,
        endPoint: wrist),
      style: StrokeStyle(
        lineWidth: art.size.height * (foreground ? 0.070 : 0.057),
        lineCap: .round,
        lineJoin: .round))

    let jointRadius = art.size.height * (foreground ? 0.045 : 0.037)
    context.fill(
      Path(ellipseIn: CGRect(
        x: elbow.x - jointRadius,
        y: elbow.y - jointRadius,
        width: jointRadius * 2,
        height: jointRadius * 2)),
      with: .radialGradient(
        Gradient(colors: [ElectrumPalette.ice, ElectrumPalette.steel]),
        center: CGPoint(x: elbow.x - jointRadius * 0.25, y: elbow.y - jointRadius * 0.35),
        startRadius: 0,
        endRadius: jointRadius))

    for index in 0..<4 {
      let spread = CGFloat(index) - 1.5
      var claw = Path()
      let start = CGPoint(
        x: wrist.x + spread * art.size.width * 0.009,
        y: wrist.y)
      claw.move(to: start)
      claw.addQuadCurve(
        to: CGPoint(
          x: start.x + clawDirection * art.size.width * (0.035 + art.pose.grip * 0.006),
          y: start.y + art.size.height * (0.050 + abs(spread) * 0.004)),
        control: CGPoint(
          x: start.x + clawDirection * art.size.width * 0.020,
          y: start.y + art.size.height * 0.018))
      context.stroke(
        claw,
        with: .linearGradient(
          Gradient(colors: [ElectrumPalette.ice, ElectrumPalette.silver]),
          startPoint: start,
          endPoint: CGPoint(x: start.x, y: start.y + art.size.height * 0.05)),
        style: StrokeStyle(
          lineWidth: art.hairline * (foreground ? 1.15 : 0.82),
          lineCap: .round,
          lineJoin: .round))
    }
  }

  // MARK: - Lighting and electricity

  private func drawSpecularAccents(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    var torsoHighlight = Path()
    torsoHighlight.move(to: art.point(0.35, 0.46, dy: art.pose.bodyLift))
    torsoHighlight.addCurve(
      to: art.point(0.64, 0.43, dy: art.pose.bodyLift),
      control1: art.point(0.43, 0.39, dy: art.pose.bodyLift),
      control2: art.point(0.56, 0.38, dy: art.pose.bodyLift))
    context.stroke(
      torsoHighlight,
      with: .linearGradient(
        Gradient(colors: [ElectrumPalette.ice.opacity(0.72), .clear]),
        startPoint: art.point(0.35, 0.43),
        endPoint: art.point(0.66, 0.46)),
      style: StrokeStyle(
        lineWidth: art.hairline * 0.85,
        lineCap: .round))

    let dx = art.pose.stretch * 0.055
    let dy = art.pose.headNod * 0.018 + art.pose.stretch * 0.035
    var snoutHighlight = Path()
    snoutHighlight.move(to: art.point(0.79 + dx, 0.205 + dy))
    snoutHighlight.addLine(to: art.point(0.92 + dx, 0.265 + dy))
    context.stroke(
      snoutHighlight,
      with: .color(ElectrumPalette.ice.opacity(0.72)),
      style: StrokeStyle(lineWidth: art.hairline * 0.8, lineCap: .round))
  }

  private func drawElectricChannels(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let opacity = 0.48 + Double(art.pose.charge) * 0.42
    var dorsal = Path()
    dorsal.move(to: art.point(0.24, 0.66, dy: art.pose.bodyLift))
    dorsal.addCurve(
      to: art.point(
        0.79 + art.pose.stretch * 0.055,
        0.205 + art.pose.headNod * 0.018 + art.pose.stretch * 0.035),
      control1: art.point(0.42, 0.66, dy: art.pose.bodyLift),
      control2: art.point(0.62, 0.34, dy: art.pose.bodyLift * 0.35))
    context.stroke(
      dorsal,
      with: .color(ElectrumPalette.electric.opacity(opacity)),
      style: StrokeStyle(
        lineWidth: art.hairline * 0.9,
        lineCap: .round,
        lineJoin: .round))

    let nodes = [
      art.point(0.33, 0.61, dy: art.pose.bodyLift),
      art.point(0.45, 0.55, dy: art.pose.bodyLift),
      art.point(0.56, 0.47, dy: art.pose.bodyLift),
      art.point(0.64, 0.34, dy: art.pose.headNod * art.size.height * 0.01),
    ]
    for (index, node) in nodes.enumerated() {
      let radius = art.size.height * (0.010 + CGFloat(index) * 0.0015 + art.pose.charge * 0.004)
      context.fill(
        Path(ellipseIn: CGRect(
          x: node.x - radius,
          y: node.y - radius,
          width: radius * 2,
          height: radius * 2)),
        with: .color(ElectrumPalette.ice.opacity(0.62 + Double(art.pose.charge) * 0.28)))
    }
  }

  private func drawFace(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let dx = art.pose.stretch * 0.055
    let dy = art.pose.headNod * 0.018 + art.pose.stretch * 0.035
    let center = art.point(0.835 + dx, 0.255 + dy)
    let width = max(2.2, art.size.width * 0.048)
    let height = max(0.65, art.size.height * 0.032 * (1 - art.pose.blink * 0.88))
    let eye = CGRect(
      x: center.x - width * 0.5,
      y: center.y - height * 0.5,
      width: width,
      height: height)
    context.fill(Path(ellipseIn: eye), with: .color(ElectrumPalette.eye))
    context.stroke(
      Path(ellipseIn: eye.insetBy(dx: -art.hairline * 0.7, dy: -art.hairline * 0.6)),
      with: .color(ElectrumPalette.electric.opacity(0.55 + Double(art.pose.charge) * 0.38)),
      lineWidth: art.hairline * 0.7)

    let pupil = CGRect(
      x: center.x + width * 0.11,
      y: center.y - height * 0.46,
      width: max(0.4, width * 0.13),
      height: max(0.55, height * 0.92))
    context.fill(Path(ellipseIn: pupil), with: .color(ElectrumPalette.deepBlue))

    let nostril = CGRect(
      x: art.size.width * (0.916 + dx),
      y: art.size.height * (0.282 + dy),
      width: max(0.75, art.size.width * 0.010),
      height: max(0.45, art.size.height * 0.007))
    context.fill(Path(ellipseIn: nostril), with: .color(ElectrumPalette.graphite.opacity(0.92)))
  }

  private func drawFreeArcs(
    context: inout GraphicsContext,
    art: ElectrumDragonArtboard
  ) {
    let intensity = min(max(art.pose.sparkIntensity, 0), 1)
    guard intensity > 0.015 else { return }

    let origins = [
      art.point(0.52 + art.pose.stretch * 0.055, 0.055),
      art.point(0.76 + art.pose.stretch * 0.055, 0.08),
      art.point(0.95, 0.19),
      art.point(0.24 + art.pose.tailSway * 0.04, 0.95),
    ]

    for (index, origin) in origins.enumerated() {
      let phase = art.pose.sparkPhase + CGFloat(index) * 1.61
      let reach = art.size.height * (0.035 + intensity * 0.055)
      var arc = Path()
      arc.move(to: origin)
      for segment in 1...4 {
        let t = CGFloat(segment) / 4
        arc.addLine(to: CGPoint(
          x: origin.x + cos(phase + t * 4.2) * reach * t,
          y: origin.y + sin(phase * 1.27 + t * 5.1) * reach * t))
      }
      context.stroke(
        arc,
        with: .color(ElectrumPalette.electric.opacity(0.30 + Double(intensity) * 0.58)),
        style: StrokeStyle(
          lineWidth: art.hairline * 0.75,
          lineCap: .round,
          lineJoin: .round))
    }
  }

  // MARK: - Geometry helpers

  private func taperedRibbon(
    points: [CGPoint],
    startWidth: CGFloat,
    endWidth: CGFloat
  ) -> Path {
    guard points.count == 4 else { return Path() }
    var left: [CGPoint] = []
    var right: [CGPoint] = []

    for index in 0...12 {
      let t = CGFloat(index) / 12
      let center = cubicPoint(points: points, t: t)
      let tangent = cubicTangent(points: points, t: t)
      let normal = normalized(CGPoint(x: -tangent.y, y: tangent.x))
      let width = startWidth + (endWidth - startWidth) * t
      left.append(offset(center, normal, width * 0.5))
      right.append(offset(center, normal, -width * 0.5))
    }

    var path = Path()
    if let first = left.first {
      path.move(to: first)
      for point in left.dropFirst() { path.addLine(to: point) }
      for point in right.reversed() { path.addLine(to: point) }
      path.closeSubpath()
    }
    return path
  }

  private func cubicPoint(points: [CGPoint], t: CGFloat) -> CGPoint {
    guard points.count == 4 else { return .zero }
    let u = 1 - t
    let x = u * u * u * points[0].x
      + 3 * u * u * t * points[1].x
      + 3 * u * t * t * points[2].x
      + t * t * t * points[3].x
    let y = u * u * u * points[0].y
      + 3 * u * u * t * points[1].y
      + 3 * u * t * t * points[2].y
      + t * t * t * points[3].y
    return CGPoint(x: x, y: y)
  }

  private func cubicTangent(points: [CGPoint], t: CGFloat) -> CGPoint {
    guard points.count == 4 else { return CGPoint(x: 1, y: 0) }
    let u = 1 - t
    let x = 3 * u * u * (points[1].x - points[0].x)
      + 6 * u * t * (points[2].x - points[1].x)
      + 3 * t * t * (points[3].x - points[2].x)
    let y = 3 * u * u * (points[1].y - points[0].y)
      + 6 * u * t * (points[2].y - points[1].y)
      + 3 * t * t * (points[3].y - points[2].y)
    return CGPoint(x: x, y: y)
  }

  private func normalized(_ point: CGPoint) -> CGPoint {
    let length = max(0.0001, hypot(point.x, point.y))
    return CGPoint(x: point.x / length, y: point.y / length)
  }

  private func offset(_ point: CGPoint, _ direction: CGPoint, _ amount: CGFloat) -> CGPoint {
    CGPoint(x: point.x + direction.x * amount, y: point.y + direction.y * amount)
  }

  private func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
  }
}

private struct ElectrumDragonArtboard {
  let size: CGSize
  let pose: ElectrumDragonPose

  var hairline: CGFloat { max(0.45, size.height * 0.009) }

  func point(
    _ x: CGFloat,
    _ y: CGFloat,
    dx: CGFloat = 0,
    dy: CGFloat = 0
  ) -> CGPoint {
    CGPoint(x: size.width * x + dx, y: size.height * y + dy)
  }
}

private struct ElectrumDragonPose {
  let breath: CGFloat
  let bodyLift: CGFloat
  let headNod: CGFloat
  let frontStride: CGFloat
  let rearStride: CGFloat
  let wingOpen: CGFloat
  let wingFold: CGFloat
  let wingFlutter: CGFloat
  let tailSway: CGFloat
  let tailHang: CGFloat
  let crestFlutter: CGFloat
  let grip: CGFloat
  let blink: CGFloat
  let charge: CGFloat
  let sparkPhase: CGFloat
  let sparkIntensity: CGFloat
  let stretch: CGFloat

  init(
    activity: StatusBarPetActivity,
    time: TimeInterval,
    crawlPhase: CGFloat,
    travelVelocity: CGFloat,
    perchBlend: CGFloat,
    sparkIntensity: CGFloat
  ) {
    let movement = min(max(travelVelocity, 0), 1)
    let perch = min(max(perchBlend, 0), 1)
    let cycle = crawlPhase * .pi * 2
    let breathWave = CGFloat(sin(time * 1.45))
    let stepWave = CGFloat(sin(Double(cycle)))
    let chargeWave = CGFloat((sin(time * 4.15) + 1) * 0.5)

    breath = breathWave * (0.55 + perch * 0.45)
    bodyLift = -abs(stepWave) * movement * 0.8 + breathWave * perch * 0.16
    headNod = CGFloat(sin(Double(cycle) + 0.55)) * movement * 0.62
      + breathWave * perch * 0.22
    frontStride = stepWave * movement
    rearStride = -stepWave * movement
    stretch = movement * 0.72 + (activity == .playing ? 0.18 : 0)

    switch activity {
    case .idle:
      wingOpen = 0.46 + CGFloat(sin(time * 1.18)) * 0.025
    case .roaming:
      wingOpen = 0.18 + abs(stepWave) * 0.10
    case .playing:
      wingOpen = 0.72 + CGFloat((sin(time * 6.8) + 1) * 0.5) * 0.12
    }

    wingFold = 1 - min(max(wingOpen, 0), 1)
    wingFlutter = CGFloat(sin(time * (activity == .playing ? 7.4 : 2.2) + Double(cycle)))
      * (0.35 + movement * 0.65)
    tailSway = CGFloat(sin(time * (activity == .idle ? 1.05 : 3.6) + Double(cycle) * 0.85))
      * (0.32 + movement * 0.68)
    tailHang = 0.76 * perch + 0.22 * (1 - perch)
    crestFlutter = CGFloat(sin(time * 4.5 + Double(cycle))) * (0.28 + movement * 0.72)
    grip = 0.58 + perch * 0.42
    blink = CGFloat(pow(max(0, sin(time * 0.67 - 1.0)), 20))
    charge = min(max(chargeWave * 0.56 + movement * 0.24 + (activity == .playing ? 0.28 : 0), 0), 1)
    sparkPhase = CGFloat(time * 4.0) + cycle
    self.sparkIntensity = min(max(sparkIntensity, 0), 1)
  }
}

private enum ElectrumPalette {
  static let graphite = Color(red: 0.055, green: 0.075, blue: 0.12)
  static let deepBlue = Color(red: 0.025, green: 0.08, blue: 0.20)
  static let cobalt = Color(red: 0.09, green: 0.27, blue: 0.58)
  static let slate = Color(red: 0.27, green: 0.35, blue: 0.48)
  static let steel = Color(red: 0.48, green: 0.57, blue: 0.68)
  static let silver = Color(red: 0.70, green: 0.79, blue: 0.89)
  static let ice = Color(red: 0.90, green: 0.97, blue: 1.0)
  static let electric = Color(red: 0.10, green: 0.62, blue: 1.0)
  static let eye = Color(red: 0.54, green: 0.94, blue: 1.0)
}
