import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/nested_page_scroll.dart';

void main() {
  Future<NestedPageScrollController> mount(
    WidgetTester tester, {
    int initialPage = 0,
    double contentHeight = 700,
  }) async {
    final controller = NestedPageScrollController(
      pageCount: 3,
      initialPage: initialPage,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: NestedPageScrollView(
                controller: controller,
                onPageChanged: (_) {},
                builder: (_, page) => SizedBox(
                  height: contentHeight,
                  child: Column(
                    children: [
                      Text('끼니 $page 상단'),
                      const Spacer(),
                      Text('끼니 $page 하단'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  Future<void> wheel(WidgetTester tester, Offset delta) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(NestedPageScrollView)),
        scrollDelta: delta,
      ),
    );
    await tester.pump();
  }

  testWidgets('휠 입력은 콘텐츠 끝에서 남은 거리에만 경계 저항을 적용한다', (tester) async {
    final controller = await mount(tester);
    await wheel(tester, const Offset(0, 350));
    // 내부 여유 302px를 소비하고 남은 48px에는 저항을 적용한다.
    expect(controller.page, greaterThan(0));
    expect(controller.page, lessThan(48 / 400));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('짧은 끼니 스크롤도 의도한 방향으로 정렬한다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(0, 100));
    final preview = controller.page!;
    expect(preview, greaterThan(0));
    expect(preview, lessThan(0.25));
    // 입력 종료를 기다리지 않고 다음 프레임부터 전환한다.
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.page, greaterThan(preview));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });

  testWidgets('연속 휠 입력 중 기준을 넘으면 끼니 전환을 시작한다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    for (var i = 0; i < 3; i++) {
      await wheel(tester, const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });

  testWidgets('전환 중 반대 입력으로 원래 끼니로 되돌릴 수 있다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 50));
    final movingPage = controller.page!;
    await wheel(tester, const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.page, lessThan(movingPage));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('이전 끼니는 하단부터 진입하고 관성 꼬리가 콘텐츠를 밀지 않는다', (tester) async {
    final controller = await mount(tester, initialPage: 1);
    await wheel(tester, const Offset(0, -450));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(controller.pageReversed(0), isTrue);
    final inner = tester.widget<SingleChildScrollView>(
      find
          .ancestor(
            of: find.text('끼니 0 상단'),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(inner.controller!.offset, 0);
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
  });

  testWidgets('콘텐츠 중간에서 시작한 드래그도 끝에서 끼니 이동으로 이어진다', (tester) async {
    final controller = await mount(tester);
    await wheel(tester, const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NestedPageScrollView)),
    );
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(controller.page!, greaterThan(0));
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pan/zoom 트랙패드 입력으로 끼니를 이동한다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    final center = tester.getCenter(find.byType(NestedPageScrollView));
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, pan: const Offset(0, -40)),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, pan: const Offset(0, -300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.page!, greaterThan(0.5));
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });

  testWidgets('경계 저항은 누적 거리와 함께 커지고 짧은 입력은 복귀한다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(0, 20));
    final first = controller.page!;
    await wheel(tester, const Offset(0, 20));
    final second = controller.page!;
    expect(second - first, lessThan(first));
    await wheel(tester, const Offset(0, -40));
    expect(controller.page, closeTo(0, 0.001));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('입력이 계속되어도 전환을 완료하고 같은 관성으로 끼니를 건너뛰지 않는다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    for (var i = 0; i < 20; i++) {
      await wheel(tester, const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 20));
    }
    // 마지막 입력으로부터 종료 대기 시간보다 짧은 시점에도 전환이 완료된다.
    expect(controller.page, 1);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });

  testWidgets('가로가 주성분인 휠 입력은 세로 끼니를 움직이지 않는다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(250, 20));
    expect(controller.page, 0);
  });

  testWidgets('첫 끼니와 마지막 끼니에서 범위 밖으로 넘어가지 않는다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(0, -500));
    expect(controller.page, 0);
    await wheel(tester, const Offset(0, 1200));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    await wheel(tester, const Offset(0, 1200));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    await wheel(tester, const Offset(0, 500));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('다음 끼니에서 이전 끼니로 돌아가면 하단부터 진입한다', (tester) async {
    final controller = await mount(tester);
    await wheel(tester, const Offset(0, 702));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    await wheel(tester, const Offset(0, -450));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    final inner = tester.widget<SingleChildScrollView>(
      find
          .ancestor(
            of: find.text('끼니 0 상단'),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(inner.reverse, isTrue);
    expect(inner.controller!.offset, 0);
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
  });

  testWidgets('버튼 이동이 진행 중인 휠 세션을 취소해 이전 타이머가 새 이동을 덮어쓰지 않는다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(0, 100));
    final move = controller.animateToPage(
      2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    await tester.pumpAndSettle();
    await move;
    expect(controller.page, 2);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.page, 2);
  });

  testWidgets('트랙패드가 레이아웃 갱신 전에 끝나도 마지막 남은 입력을 보존한다', (tester) async {
    final controller = await mount(tester);
    controller.jumpToPage(1);
    await tester.pumpAndSettle();
    final pointer = TestPointer(2, PointerDeviceKind.trackpad);
    final center = tester.getCenter(find.byType(NestedPageScrollView));
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, pan: const Offset(0, 40)),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, pan: const Offset(0, 450)),
    );
    // reverse 변경을 그릴 프레임 전에 손을 놓는 상황.
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    final inner = tester.widget<SingleChildScrollView>(
      find
          .ancestor(
            of: find.text('끼니 0 상단'),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    expect(inner.reverse, isTrue);
    expect(inner.controller!.offset, 0);
  });

  testWidgets('아직 화면에 붙지 않은 요일도 그룹 버튼의 목표 끼니로 시작한다', (tester) async {
    final group = NestedPageScrollControllerGroup(count: 2, pageCount: 3);
    addTearDown(group.dispose);
    await group.animateToPage(
      2,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: NestedPageScrollView(
            controller: group.getController(1),
            onPageChanged: (_) {},
            builder: (_, index) => Text('끼니 $index'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(group.getController(1).page, 2);
  });

  testWidgets('휠 종료 타이머가 남아 있어도 화면 이탈 시 안전하게 정리한다', (tester) async {
    await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(0, 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
