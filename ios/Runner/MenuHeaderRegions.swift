import Flutter
import UIKit

final class MenuHeaderRegions: NSObject, FlutterStreamHandler {
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "MenuHeaderRegions") else { return }
    let channel = FlutterEventChannel(
      name: "pro.hexa.meal.meal_client/menu_header_regions",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(MenuHeaderRegions(registrar: registrar))
  }

  private let registrar: FlutterPluginRegistrar
  private var observer: UIView?

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    #if canImport(UIKit, _version: 9127.0.85)
    if #available(iOS 27.1, *), let view = registrar.viewController?.view {
      let probe = HeaderRegionObserver(frame: view.bounds)
      probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      probe.isUserInteractionEnabled = false
      probe.accessibilityElementsHidden = true
      probe.publish = events
      view.addSubview(probe)
      observer = probe
      probe.setNeedsUpdateConstraints()
    }
    #endif
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observer?.removeFromSuperview()
    observer = nil
    return nil
  }
}

#if canImport(UIKit, _version: 9127.0.85)
@available(iOS 27.1, *)
private final class HeaderRegionObserver: UIView {
  var publish: FlutterEventSink?
  private var previous: [Double]?

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsUpdateConstraints()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    reportRegions()
  }

  override func updateConstraints() {
    reportRegions()
    super.updateConstraints()
  }

  private func reportRegions() {
    let snapshot = headerRegion()
    guard snapshot != previous else { return }
    previous = snapshot
    publish?(snapshot)
  }

  private func headerRegion() -> [Double] {
    let top = safeAreaInsets.top
    guard let scene = window?.windowScene, let manager = scene.statusBarManager,
          bounds.height > bounds.width, top > 0 else { return [] }

    // 완전히 펼친 내부 화면에서는 접힘 영역이 비활성 상태로 남는다.
    let divisions = reservedRegions(kind: .division, options: .includeInactive)
    guard !divisions.isEmpty, divisions.allSatisfy({ !$0.isActive }) else { return [] }

    let band = CGRect(x: 0, y: 0, width: bounds.width, height: top)
    // 상태 막대 좌표는 장면 기준이며, 카메라가 꺼져 있어도 조회할 수 있다.
    let status = convert(manager.statusBarFrame, from: scene.coordinateSpace).intersection(bounds)
    guard !status.isEmpty, status.intersects(band), status.minX > bounds.midX else { return [] }
    let occupied = reservedRegions(kind: .occlusion)
      .map { $0.frame.intersection(bounds) }
      .filter { $0.intersects(band) }
      .reduce(status) { $0.union($1) }
    guard occupied.minX > bounds.midX else { return [] }
    return [bounds.width, bounds.height, top, occupied.minX, occupied.midY, occupied.maxY]
      .map { Double($0) }
  }
}
#endif
