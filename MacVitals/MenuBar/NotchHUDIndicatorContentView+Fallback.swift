import CoreGraphics

extension NotchHUDIndicatorContentView {
  init(
    snapshot: SystemSnapshot,
    configuration: NotchHUDConfiguration,
    safeAreaTop: CGFloat
  ) {
    self.init(
      snapshot: snapshot,
      configuration: configuration,
      safeAreaTop: safeAreaTop,
      notchWidth: NotchHUDLayout.notchWidth)
  }
}
