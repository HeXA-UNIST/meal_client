import Flutter
import UIKit

final class MenuFlutterViewController: FlutterViewController {
  private(set) lazy var regions = MenuHeaderRegions(controller: self)

  override func viewDidLoad() {
    super.viewDidLoad()
    let channel = FlutterEventChannel(
      name: "pro.hexa.meal.meal_client/menu_header_regions", binaryMessenger: binaryMessenger)
    channel.setStreamHandler(regions)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    regions.publish()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    regions.publish()
  }
}

@MainActor
final class MenuHeaderRegions: NSObject, @preconcurrency FlutterStreamHandler {
  private weak var controller: MenuFlutterViewController?
  private var guide: UILayoutGuide?
  private var sink: FlutterEventSink?
  private(set) var lastPublished: [Double]?

  init(controller: MenuFlutterViewController) {
    self.controller = controller
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError? {
    guard let height = arguments as? NSNumber, let view = controller?.view else {
      return FlutterError(code: "HEADER_UNAVAILABLE", message: "Missing toolbar height or view", details: nil)
    }
    guide = BapuTopBarGuide(view, CGFloat(height.doubleValue))
    sink = events
    view.setNeedsLayout()
    view.layoutIfNeeded()
    publish()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    lastPublished = nil
    guide = nil
    return nil
  }

  func publish() {
    guard let sink else { return }
    let value = snapshot()
    guard lastPublished != value else { return }
    lastPublished = value
    sink(value)
  }

  private func snapshot() -> [Double] {
    guard let view = controller?.viewIfLoaded, view.window != nil, let guide,
          view.traitCollection.userInterfaceIdiom == .phone,
          view.traitCollection.horizontalSizeClass == .regular,
          view.bounds.height > view.bounds.width else { return [] }
    let frame = guide.layoutFrame
    // 초기 레이아웃에서 시계 쪽 여백이 아직 반영되지 않은 가이드는 건너뛴다.
    guard !frame.isEmpty, view.bounds.contains(frame),
          view.bounds.maxX - frame.maxX > frame.minX - view.bounds.minX,
          frame.minY < view.safeAreaInsets.top else { return [] }
    return [view.bounds.width, view.bounds.height, view.safeAreaInsets.top,
            frame.minX, frame.minY, frame.width, frame.height].map { Double($0) }
  }
}
