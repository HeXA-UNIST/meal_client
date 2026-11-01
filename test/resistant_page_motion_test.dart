import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:meal_client/features/home/resistant_page_motion.dart';

void main() {
  Future<(PageController, ResistantPageMotion)> mount(
    WidgetTester tester,
  ) async {
    final controller = PageController();
    final motion = ResistantPageMotion();
    addTearDown(controller.dispose);
    addTearDown(motion.cancel);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: PageView(
              controller: controller,
              scrollDirection: Axis.vertical,
              physics: const NeverScrollableScrollPhysics(),
              children: const [Text('아침'), Text('점심'), Text('저녁')],
            ),
          ),
        ),
      ),
    );
    return (controller, motion);
  }

  void move(
    PageController controller,
    ResistantPageMotion motion,
    double distance,
    int milliseconds, {
    bool wheel = false,
  }) {
    motion.update(
      controller.position,
      DragUpdateDetails(
        globalPosition: Offset.zero,
        sourceTimeStamp: Duration(milliseconds: milliseconds),
        delta: Offset(0, -distance),
        primaryDelta: -distance,
      ),
      pointerScrolling: wheel,
    );
  }

  testWidgets('드래그는 기준을 넘어도 손을 놓기 전에는 자동 전환하지 않는다', (tester) async {
    final (controller, motion) = await mount(tester);
    move(controller, motion, 100, 20);
    expect(controller.page, closeTo(0.25, 0.001));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.page, closeTo(0.25, 0.001));
    move(controller, motion, -60, 40);
    expect(controller.page, closeTo(0.1, 0.001));
    motion.finish();
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('짧은 드래그도 종료 속도를 페이지 물리에 전달해 다음 끼니로 넘긴다', (tester) async {
    final (controller, motion) = await mount(tester);
    move(controller, motion, 60, 20);
    motion.finish(velocity: -900);
    await tester.pump();
    final released = controller.position.pixels;
    await tester.pump(const Duration(milliseconds: 1));
    // 종료 속도로 시작하며 고정 시간 곡선의 시작 속도로 바뀌지 않는다.
    expect((controller.position.pixels - released) * 1000, closeTo(900, 100));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });

  testWidgets('드래그 절반을 넘긴 뒤 속도 없이 놓아도 가까운 페이지로 정렬한다', (tester) async {
    final (controller, motion) = await mount(tester);
    move(controller, motion, 240, 20);
    motion.finish();
    await tester.pumpAndSettle();
    expect(controller.page, 1);
  });

  for (final wheel in [false, true]) {
    testWidgets('정렬 중 ${wheel ? '휠' : '터치'} 재입력은 현재 위치에서 이어지고 인접 목적지에 멈춘다', (
      tester,
    ) async {
      final (controller, motion) = await mount(tester);
      move(controller, motion, 100, 0, wheel: true);
      motion.finish();
      expect(motion.isInputActive, isFalse);
      expect(motion.isSettling, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final before = controller.position.pixels;
      expect(before, greaterThan(200));
      move(controller, motion, 8, 140, wheel: wheel);
      expect(controller.position.pixels, greaterThan(before));
      expect(controller.position.pixels - before, lessThanOrEqualTo(8.01));
      expect(motion.isInputActive, isTrue);
      if (wheel) move(controller, motion, 80, 160, wheel: true);
      motion.finish();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(motion.isSettling, isFalse);
    });
  }

  testWidgets('입력 종료 후 진행 중인 정렬도 취소할 수 있다', (tester) async {
    final (controller, motion) = await mount(tester);
    move(controller, motion, 100, 0, wheel: true);
    motion.finish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    motion.cancel();
    final stopped = controller.position.pixels;
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.position.pixels, stopped);
    expect(motion.isInputActive, isFalse);
    expect(motion.isSettling, isFalse);
  });

  for (final singleEvent in [true, false]) {
    testWidgets('${singleEvent ? '첫' : '느린 연속'} 휠 전환은 처음부터 이동하고 중간에 가속하지 않는다', (
      tester,
    ) async {
      final (controller, motion) = await mount(tester);
      if (singleEvent) {
        move(controller, motion, 100, 0, wheel: true);
      } else {
        move(controller, motion, 30, 0, wheel: true);
        move(controller, motion, 30, 40, wheel: true);
        move(controller, motion, 20, 80, wheel: true);
      }
      var previous = controller.position.pixels;
      final distance = 400 - previous;
      var previousStep = double.infinity;
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final current = controller.position.pixels;
        final step = current - previous;
        expect(step, greaterThanOrEqualTo(0));
        expect(step, lessThanOrEqualTo(previousStep + 0.01));
        if (i == 0) {
          // 첫 구간부터 충분히 이동하며 끝으로 갈수록 감속한다.
          expect(step / distance, greaterThan(0.2));
        }
        previousStep = step;
        previous = current;
      }
      motion.finish();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });
  }
}
