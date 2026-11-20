# iPhone Duo에서 시계 옆에 식단 헤더 배치하기

밥먹어U에서는 iPhone Duo를 펼쳐 세로로 들었을 때 메뉴 버튼, 날짜, 끼니 전환 버튼을 시스템 시계 왼쪽에 한 줄로 표시한다. 요일 탭부터는 화면 너비를 모두 쓴다. Apple도 펼친 내부 화면의 세로 방향에서는 가로형 바를 유지한다. 접은 화면과 펼친 가로 화면에서는 시스템 바가 화면 옆에 올 수 있다. [Apple 디자인 가이드](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

## 상단에 한 줄이 비었던 이유

공개 시뮬레이터 측정에서 펼친 내부 화면은 세로로 669 × 951pt였고, Flutter가 보고한 상단 여백은 82pt였다. 같은 자세에서 네이티브 앱이 관측한 시계와 상태 아이콘의 가림 영역은 창의 오른쪽 위 134 × 82pt였다. 일반적인 Flutter AppBar는 상단 여백 82pt를 화면 전체에 적용하므로 시계 왼쪽도 함께 비운다. 이 측정값은 당시 시뮬레이터의 예이며 앱은 실행 중인 창에서 UIKit이 제시하는 배치 영역을 읽는다. [Flutter 측정값과 화면](https://vibeview.io/guides/flutter-iphone-duo/) · [네이티브 앱의 측정값](https://foldhunt.com/guides/everything-your-agent-needs-for-iphone-duo/)

기존 커밋 `18e3d250`은 접힘 영역이 비활성 상태이고 `statusBarFrame`이 화면 오른쪽 절반에서 시작할 때만 가림 영역을 읽었다. Apple은 이 프레임을 상태 표시줄의 경계로 정의한다. 시계와 아이콘만 둘러싸는 좌표라고 가정하면 쓸 수 있는 공간도 놓칠 수 있다. 사용자 시뮬레이터에서는 커밋 전후 모두 시계 아래에 헤더가 나타났다. 그 실행의 네이티브 반환값은 기록하지 않아 어느 조건에서 기본 헤더로 돌아갔는지는 확인할 수 없다. 기존 위젯 테스트는 유효한 가상 좌표를 Flutter에 직접 전달했다. [기존 구현](https://github.com/HeXA-UNIST/meal_client/blob/18e3d250/ios/Runner/MenuHeaderRegions.swift) · [Apple의 statusBarFrame 정의](https://developer.apple.com/documentation/uikit/uistatusbarmanager/statusbarframe)

## UIKit과 Flutter 연결

Apple은 커스텀 바를 배치할 때 `UIView.LayoutRegion.bar(onEdge:extent:)`와 `layoutGuide(for:)`를 안내한다. `window_placement`는 이 가이드를 Flutter 뷰에서 조회해 창 좌표의 사각형을 Dart로 전달한다. `duo_navigation`은 상단 바가 차지할 수 있는 사각형으로 제목과 액션을 시계 옆에 배치한다. [Apple 프레임워크 엔지니어의 설명](https://developer.apple.com/forums/thread/847835) · [window_placement의 Swift 구현](https://github.com/JanMichaelPeter/window_placement/blob/main/ios/window_placement/Sources/window_placement/WindowPlacementPlugin.swift) · [duo_navigation의 제목 바 배치 계산](https://github.com/JanMichaelPeter/duo_navigation/blob/main/lib/src/geometry/bar_regions.dart)

`iphone_duo`는 창이 변한 뒤 iOS가 상태 영역을 다시 배치하는 경우를 다룬다. `liquid_glass_widgets`에서는 실기기의 Live Activity가 상태 영역을 확장하면서 고정 여백이 부족해져, UIKit의 가림 영역을 읽도록 수정했다. 밥먹어U는 UIKit의 레이아웃이 끝날 때마다 가이드를 읽고 값이 달라졌을 때 Flutter에 전달한다. [iphone_duo의 구현 설명](https://pub.dev/packages/iphone_duo) · [liquid_glass_widgets의 실기기 수정](https://github.com/sdegenaar/liquid_glass_widgets/pull/405/files)

Flutter 홈이 헤더 높이 52를 전달하면 iOS 뷰 컨트롤러가 해당 높이의 상단 가이드를 구한다. 앱은 가로 크기 클래스가 regular인 세로 iPhone 창에서 가이드가 상단 여백 안으로 들어올 때 이 사각형을 사용한다. 첫 줄은 사각형의 좌우 경계를 따르고, 요일 탭은 가이드와 상단 여백이 모두 끝나는 위치에서 시작한다. 회전 직후 좌표가 현재 창과 다르거나 글자를 키워 첫 줄의 폭이 부족하면 기본 헤더를 쓴다. [네이티브 브리지](../../ios/Runner/MenuHeaderRegions.swift) · [좌표 검증](../../lib/features/home/menu_header_region.dart) · [홈 레이아웃](../../lib/features/home/week_menu_scaffold.dart)

## 시뮬레이터에서 확인하기

1. Xcode에서 Runner의 빌드 SDK와 Duo 시뮬레이터의 iOS 버전이 모두 27.1 이상인지 확인한다. 앱이 양쪽 디스플레이 전체를 활용하는 방식은 빌드 SDK에 따라 달라진다. [Apple의 SDK별 동작 설명](https://developer.apple.com/iphone-duo/prepare/)
2. Device Hub에서 Duo를 완전히 펼치고 **내부 화면이 세로로 긴 상태**에서 홈을 연다. 날짜와 끼니 버튼의 세로 중심이 시계 옆에 오는지, 메뉴 버튼과 끼니 버튼을 탭할 수 있는지, 요일 탭이 시계 아래에서 오른쪽 끝까지 이어지는지 확인한다. [Device Hub 조작 방법](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub)
3. 같은 자세에서 Runner 스킴의 RunnerTests를 실행한다. Duo 테스트는 Flutter 홈이 실제로 구독한 뒤 브리지가 발행한 좌표와 창 너비, 상단 여백, 시계 쪽 여유 폭을 확인한다. 다른 자세에서 건너뛴 결과는 이 배치의 통과로 집계하지 않는다. [RunnerTests](../../ios/RunnerTests/RunnerTests.swift)
4. 가로로 돌렸다가 세로로 돌아온 뒤 날짜와 끼니 버튼이 다시 시계 왼쪽에 놓이는지 확인한다. 다음 주 미리보기를 열고 닫는 동안에는 뒤로가기 버튼, 날짜, 끼니 버튼이 잠시 숨고 요일 탭과 식단 카드는 같은 높이를 유지해야 한다. 뒤로 밀기를 취소하면 세 항목이 다시 나타나고 끼니 버튼을 누를 수 있어야 한다. [홈 테스트](../../test/week_menu_scaffold_test.dart) · [다음 주 미리보기 테스트](../../test/next_week_preview_page_test.dart)

Windows에서 3배율 화면의 1픽셀 높이 오차, 채널 오류 뒤 좌표 복구, 다음 주 미리보기에서 뒤로 밀기를 취소한 뒤 버튼 복원을 포함한 관련 Flutter 테스트 12개가 통과했다. iOS 빌드와 Duo 시뮬레이터에서의 실제 배치는 아직 검증하지 않았다. [채널 복구 테스트](../../test/menu_header_region_test.dart)
