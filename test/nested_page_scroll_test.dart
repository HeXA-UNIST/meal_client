import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/nested_page_scroll.dart';
import 'package:meal_client/features/home/pointer_scroll_session.dart';

void main() {
  Future<NestedPageScrollController> mount(
    WidgetTester tester, {
    double contentHeight = 700,
    PointerScrollSession? pointerSession,
    bool Function()? consumeSignal,
    bool Function()? horizontalActive,
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
                pointerSession: pointerSession,
                isHorizontalInputActive: horizontalActive,
                onPageChanged: (_) {},
                builder: (_, page) => Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (event) {
                    if (consumeSignal?.call() ?? false) {
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (_) {},
                      );
                    }
                  },
                  child: SizedBox(
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

  testWidgets('자식이 소비한 휠은 공유 세션의 축을 잠그지 않는다', (tester) async {
    final session = PointerScrollSession();
    addTearDown(session.reset);
    var consume = true;
    await mount(tester, pointerSession: session, consumeSignal: () => consume);
    await wheel(tester, const Offset(0, 40));
    expect(session.axis, isNull);
    expect(
      session.peekAxis(const Offset(40, 0), shifted: false),
      Axis.horizontal,
    );
    consume = false;
    await wheel(tester, const Offset(0, 40));
    expect(session.axis, Axis.vertical);
    await tester.pump(PointerScrollSession.singleIdleDuration);
    await tester.pumpAndSettle();
    expect(session.axis, isNull);
  });

  testWidgets('가로 활동으로 차단된 대각선 휠도 세로 세션 축을 유지한다', (tester) async {
    final session = PointerScrollSession();
    addTearDown(session.reset);
    var active = false;
    await mount(
      tester,
      pointerSession: session,
      horizontalActive: () => active,
    );
    await wheel(tester, const Offset(0, 40));
    expect(session.axis, Axis.vertical);
    active = true;
    await wheel(tester, const Offset(60, 40));
    expect(session.axis, Axis.vertical);
    await wheel(tester, const Offset(60, 40));
    expect(session.axis, Axis.vertical);
    await tester.pump(PointerScrollSession.singleIdleDuration);
    await tester.pumpAndSettle();
    expect(session.axis, isNull);
  });

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
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    final activity = controller.position.activity;
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(controller.position.activity, same(activity));
    }
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(controller.page, 0);
    expect(inner.offset, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
  });
  testWidgets('미확정 경계 이동을 되돌리고 남은 휠 입력은 본문에 전달한다', (tester) async {
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
    await wheel(tester, Offset(0, inner.position.maxScrollExtent + 48));
    expect(controller.page, greaterThan(0));
    await wheel(tester, const Offset(0, -100));
    expect(controller.page, 0);
    expect(inner.offset, closeTo(inner.position.maxScrollExtent - 52, 0.01));
    await tester.pumpAndSettle();
  });

  testWidgets('마우스 휠 한 칸은 본문 끝까지 먼저 쓰고 남은 거리만 페이지에 전달한다', (tester) async {
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
    inner.jumpTo(inner.position.maxScrollExtent - 25);
    await wheel(tester, const Offset(0, 50));
    await tester.pump(const Duration(milliseconds: 181));
    await tester.pumpAndSettle();
    expect(inner.offset, inner.position.maxScrollExtent);
    expect(controller.page, 0);
    await wheel(tester, const Offset(0, 50));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });

  for (final waitForLayout in [false, true]) {
    testWidgets(
      '끼니 배치 ${waitForLayout ? "후" : "전"}에도 작은 휠 두 건을 한 칸으로 합치지 않는다',
      (tester) async {
        final controller = await mount(tester, contentHeight: 100);
        controller.jumpToPage(1);
        if (waitForLayout) await tester.pump();
        final center = tester.getCenter(find.byType(NestedPageScrollView));
        for (var i = 0; i < 2; i++) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: center,
              scrollDelta: const Offset(0, 25),
            ),
          );
        }
        await tester.pump();
        await tester.pump(PointerScrollSession.singleIdleDuration);
        await tester.pumpAndSettle();
        expect(controller.page, 1);
      },
    );
  }

  testWidgets('전환 중 반대 입력으로 원래 끼니로 되돌릴 수 있다', (tester) async {
    final controller = await mount(tester, contentHeight: 100);
    await wheel(tester, const Offset(0, 50));
    await tester.pump(const Duration(milliseconds: 50));
    final movingPage = controller.page!;
    await wheel(tester, const Offset(0, -50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.page, lessThan(movingPage));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('정렬 직후의 짧은 반전은 첫 입력부터 현재 본문을 읽는다', (tester) async {
    final controller = await mount(tester);
    await wheel(tester, const Offset(0, 702));
    for (final tail in [12.0, 6.0]) {
      await tester.pump(const Duration(milliseconds: 10));
      await wheel(tester, Offset(0, tail));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final inner = tester
        .widget<SingleChildScrollView>(
          find
              .ancestor(
                of: find.text('끼니 1 상단'),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        )
        .controller!;
    inner.jumpTo(120);
    for (final expected in [80, 40]) {
      await wheel(tester, const Offset(0, -40));
      expect(inner.offset, expected);
      expect(controller.page, 1);
    }
    await wheel(tester, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(find.text('끼니 0 하단').hitTestable(), findsOneWidget);
  });

  testWidgets('같은 컨트롤러로 뷰를 교체한 뒤에도 휠 입력을 받고 취소할 수 있다', (tester) async {
    final controller = NestedPageScrollController(pageCount: 3);
    addTearDown(controller.dispose);
    final session = PointerScrollSession();
    Widget view(int key) => MaterialApp(
      home: NestedPageScrollView(
        key: ValueKey(key),
        controller: controller,
        pointerSession: session,
        wheelTargetFor: (axis, _) =>
            axis == Axis.vertical ? controller.wheelTarget : null,
        onPageChanged: (_) {},
        builder: (_, page) => Text('끼니 $page'),
      ),
    );
    await tester.pumpWidget(view(0));
    await tester.pumpWidget(view(1));
    await wheel(tester, const Offset(0, 40));
    expect(controller.page, greaterThan(0));
    controller.cancelUserInput();
    // 취소 전에 움직인 40px가 다음 40px에 더해지면 끼니가 넘어간다.
    await wheel(tester, const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('본문 배치를 기다리던 뷰가 교체되면 새 뷰가 첫 휠 입력을 받는다', (tester) async {
    final session = PointerScrollSession();
    final before = NestedPageScrollController(pageCount: 3);
    final after = NestedPageScrollController(pageCount: 3);
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    Widget view(NestedPageScrollController controller) => MaterialApp(
      home: NestedPageScrollView(
        key: ObjectKey(controller),
        controller: controller,
        pointerSession: session,
        onPageChanged: (_) {},
        builder: (_, page) => Text('끼니 $page'),
      ),
    );
    await tester.pumpWidget(view(before));
    before.jumpToPage(1);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(NestedPageScrollView)),
        scrollDelta: const Offset(0, 50),
      ),
    );
    await tester.pumpWidget(view(after));
    expect(after.page, 0);
    await wheel(tester, const Offset(0, 50));
    await tester.pumpAndSettle();
    expect(after.page, 1);
  });

  for (final queued in [false, true]) {
    testWidgets('다른 뷰가 공유 세션을 떠나도 ${queued ? "대기 중인" : "처리 중인"} 휠 입력을 이어 간다', (
      tester,
    ) async {
      final controllers = List.generate(
        2,
        (_) => NestedPageScrollController(pageCount: 3),
      );
      final shared = PointerScrollSession();
      final replacement = PointerScrollSession();
      addTearDown(() {
        for (final controller in controllers) {
          controller.dispose();
        }
      });
      Widget views(PointerScrollSession left) => MaterialApp(
        home: Row(
          children: [
            for (var i = 0; i < 2; i++)
              Expanded(
                child: NestedPageScrollView(
                  controller: controllers[i],
                  pointerSession: i == 0 ? left : shared,
                  onPageChanged: (_) {},
                  builder: (_, page) => Text('끼니 $page'),
                ),
              ),
          ],
        ),
      );
      await tester.pumpWidget(views(shared));
      if (queued) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(NestedPageScrollView).first),
            scrollDelta: const Offset(0, 80),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      Future<void> rightWheel() async {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(NestedPageScrollView).last),
            scrollDelta: const Offset(0, 40),
          ),
        );
        await tester.pump();
      }

      await rightWheel();
      await tester.pumpWidget(views(replacement));
      expect(shared.axis, Axis.vertical);
      await rightWheel();
      await tester.pumpAndSettle();
      expect(controllers.last.page, 1);
    });
  }

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
    await wheel(tester, const Offset(0, 100));
    final preview = controller.page!;
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.page, greaterThan(preview));
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

  testWidgets('스크린 리더 showOnScreen 탐색으로 화면 밖 하단 콘텐츠를 노출한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final controller = await mount(tester, contentHeight: 700);
      final viewport = tester.getRect(find.byType(NestedPageScrollView));
      expect(
        tester.getRect(find.text('끼니 0 하단')).bottom,
        greaterThan(viewport.bottom),
      );

      final bottomNode = tester.getSemantics(find.text('끼니 0 하단'));
      tester
          .renderObject(find.text('끼니 0 하단'))
          .owner!
          .semanticsOwner!
          .performAction(bottomNode.id, SemanticsAction.showOnScreen);
      await tester.pumpAndSettle();

      expect(controller.page, 0);
      expect(
        tester.getRect(find.text('끼니 0 하단')).bottom,
        lessThanOrEqualTo(viewport.bottom + 0.01),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('시맨틱 세로 스크롤은 본문 하단을 먼저 보여주고 다음 액션에서 끼니를 넘긴다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      // 뷰포트(400)보다 100px만 넘치는 본문: 한 번에 0.8*400=320px가 들어와도
      // 같은 액션에서 다음 끼니로 건너뛰지 않아야 한다.
      final controller = await mount(tester, contentHeight: 500);
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
      final gestureFinder = find
          .descendant(
            of: find.byType(NestedPageScrollView),
            matching: find.byType(GestureDetector),
          )
          .first;
      final scrollNode = tester.getSemantics(gestureFinder);
      expect(
        scrollNode.getSemanticsData().hasAction(SemanticsAction.scrollUp),
        isTrue,
      );

      final semanticsOwner = tester
          .renderObject(gestureFinder)
          .owner!
          .semanticsOwner!;
      semanticsOwner.performAction(scrollNode.id, SemanticsAction.scrollUp);
      await tester.pumpAndSettle();

      expect(controller.page, 0);
      expect(inner.offset, closeTo(100, 0.01));

      semanticsOwner.performAction(scrollNode.id, SemanticsAction.scrollUp);
      await tester.pumpAndSettle();

      expect(controller.page, 1);
    } finally {
      semantics.dispose();
    }
  });
}
