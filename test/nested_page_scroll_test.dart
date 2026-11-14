import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/nested_page_scroll.dart';

void main() {
  Future<NestedPageScrollController> mount(
    WidgetTester tester, {
    double contentHeight = 700,
  }) async {
    final controller = NestedPageScrollController(pageCount: 3);
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

  testWidgets('범위 밖 터치 입력을 반전하면 현재 끼니 본문을 읽는다', (tester) async {
    final controller = await mount(tester);
    final inner = tester
        .widget<SingleChildScrollView>(
          find
              .ancestor(
                of: find.text('끼니 0 상단'),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        )
        .controller!;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(NestedPageScrollView)),
    );
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(controller.page, 0);
    expect(inner.offset, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
  });
  testWidgets('미확정 경계 이동을 되돌리고 남은 휠 입력은 본문에 전달한다', (tester) async {
    final controller = await mount(tester);
    await wheel(tester, const Offset(0, 350));
    expect(controller.page, greaterThan(0));
    await wheel(tester, const Offset(0, -100));
    expect(controller.page, 0);
    final inner = tester
        .widget<SingleChildScrollView>(
          find
              .ancestor(
                of: find.text('끼니 0 상단'),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        )
        .controller!;
    expect(inner.offset, closeTo(inner.position.maxScrollExtent - 52, 0.01));
    await tester.pumpAndSettle();
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
}
