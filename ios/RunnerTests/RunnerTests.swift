import Flutter
import UIKit
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  @MainActor
  func test펼친Duo세로에서홈이상단바영역을구독한다() async throws {
    guard #available(iOS 27.1, *) else {
      throw XCTSkip("iOS 27.1 이상에서 실행한다.")
    }
    let root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.compactMap { $0.rootViewController }.first { $0 is FlutterViewController }
    let controller = try XCTUnwrap(root as? MenuFlutterViewController)
    let view = try XCTUnwrap(controller.viewIfLoaded)
    guard view.traitCollection.userInterfaceIdiom == .phone,
          view.traitCollection.horizontalSizeClass == .regular,
          view.bounds.height > view.bounds.width else {
      throw XCTSkip("Duo를 완전히 펼치고 내부 화면을 세로로 돌린 뒤 실행한다.")
    }

    // Flutter 홈이 구독하고 UIKit이 레이아웃을 마친 뒤 실제 전송값을 확인한다.
    let deadline = Date().addingTimeInterval(10)
    while controller.regions.lastPublished?.count != 7 && Date() < deadline {
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    let values = try XCTUnwrap(controller.regions.lastPublished)
    XCTAssertEqual(values.count, 7)
    guard values.count == 7 else { return }
    let frame = CGRect(x: values[3], y: values[4], width: values[5], height: values[6])
    XCTAssertEqual(values[0], Double(view.bounds.width), accuracy: 1)
    XCTAssertEqual(values[1], Double(view.bounds.height), accuracy: 1)
    XCTAssertLessThan(frame.minY, view.safeAreaInsets.top)
    XCTAssertGreaterThanOrEqual(frame.height, 52)
    XCTAssertGreaterThanOrEqual(frame.width, 316)
    XCTAssertGreaterThan(view.bounds.width - frame.maxX, frame.minX)
  }
}
