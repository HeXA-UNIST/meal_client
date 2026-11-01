import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/home_app_bar.dart';
import 'package:meal_client/features/home/nested_page_scroll.dart';
import 'package:meal_client/features/home/week_menu_scaffold.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    DayOfWeek initialDay = DayOfWeek.mon,
    Future<void> Function()? onNextWeek,
  }) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime.utc(2026, 10, 5),
          initialDayOfWeek: initialDay,
          onNextWeekRequested: onNextWeek,
          initialMealOfDay: MealOfDay.breakfast,
          mealFuture: Future.value(WeekMeal.empty()),
          appInfo: Future.value(
            AppInfo.fromJson({
              'announcement': null,
              'operatingHours': {
                'weekday': <String, dynamic>{},
                'weekend': <String, dynamic>{},
              },
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> wheel(WidgetTester tester, Offset delta) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(position: const Offset(200, 300), scrollDelta: delta),
    );
    await tester.pump();
  }

  testWidgets('대각선 휠은 세션 중 성분 크기가 바뀌어도 처음 선택한 축을 유지한다', (tester) async {
    await mount(tester);
    final tab = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    await wheel(tester, const Offset(35, 20));
    await tester.pump(const Duration(milliseconds: 20));
    await wheel(tester, const Offset(40, 90));
    await tester.pumpAndSettle();
    expect(tab.index, 1);
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '아침',
    );
    await wheel(tester, const Offset(20, 35));
    await tester.pump(const Duration(milliseconds: 20));
    await wheel(tester, const Offset(90, 40));
    await tester.pumpAndSettle();
    expect(tab.index, 1);
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '점심',
    );
  });

  testWidgets('일요일 도착과 같은 휠 관성은 다음 주를 열지 않고 새 세션만 연다', (tester) async {
    var opened = 0;
    await mount(
      tester,
      initialDay: DayOfWeek.sat,
      onNextWeek: () async {
        opened++;
      },
    );
    for (var i = 0; i < 12; i++) {
      await wheel(tester, const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 6);
    expect(opened, 0);
    await wheel(tester, const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await wheel(tester, const Offset(80, 0));
    expect(opened, 0);
    await tester.pump(const Duration(milliseconds: 170));
    expect(opened, 0);
    await tester.pump(const Duration(milliseconds: 20));
    expect(opened, 1);
  });

  testWidgets('주 경계에서 짧은 입력과 반대 입력은 다음 주를 열지 않는다', (tester) async {
    var opened = 0;
    await mount(
      tester,
      initialDay: DayOfWeek.sun,
      onNextWeek: () async {
        opened++;
      },
    );
    await wheel(tester, const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(opened, 0);
    await wheel(tester, const Offset(150, 0));
    await wheel(tester, const Offset(-100, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });

  testWidgets('주 경계 터치는 해제할 때만 열리고 취소하면 열리지 않는다', (tester) async {
    var opened = 0;
    await mount(
      tester,
      initialDay: DayOfWeek.sun,
      onNextWeek: () async {
        opened++;
      },
    );
    var gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    expect(opened, 0);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(opened, 0);
    gesture = await tester.startGesture(const Offset(350, 300));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-160, 0));
    await tester.pump();
    expect(opened, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('다음 주 화면이 열려 있는 동안 중복 진입하지 않는다', (tester) async {
    var opened = 0;
    final route = Completer<void>();
    await mount(
      tester,
      initialDay: DayOfWeek.sun,
      onNextWeek: () {
        opened++;
        return route.future;
      },
    );
    await wheel(tester, const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await wheel(tester, const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(opened, 1);
    route.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('주 경계 대기 중 요일 탭을 누르면 진입을 취소한다', (tester) async {
    var opened = 0;
    await mount(
      tester,
      initialDay: DayOfWeek.sun,
      onNextWeek: () async {
        opened++;
      },
    );
    await wheel(tester, const Offset(150, 0));
    await tester.tap(find.text('월'));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
  });

  testWidgets('미리보기처럼 다음 주 콜백이 없는 화면은 일요일에서 멈춘다', (tester) async {
    await mount(tester, initialDay: DayOfWeek.sun);
    await wheel(tester, const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 6);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final horizontalWheel in [false, true]) {
    for (final verticalInput in ['터치', '휠', 'pan/zoom']) {
      testWidgets(
        '가로 ${horizontalWheel ? '휠' : '드래그'} 정렬 중 세로 $verticalInput 입력을 차단한다',
        (tester) async {
          await mount(tester);
          final horizontal = tester
              .widgetList<PageView>(find.byType(PageView))
              .singleWhere((view) => view.scrollDirection == Axis.horizontal)
              .controller!;
          final tab = tester.widget<TabBar>(find.byType(TabBar)).controller!;
          if (horizontalWheel) {
            await tester.sendEventToBinding(
              const PointerScrollEvent(
                position: Offset(200, 300),
                scrollDelta: Offset(100, 0),
              ),
            );
            await tester.pump();
            // 휠 세션의 타이머가 끝나도 300ms 페이지 정렬은 진행 중이다.
            await tester.pump(const Duration(milliseconds: 190));
          } else {
            final gesture = await tester.startGesture(const Offset(200, 300));
            await gesture.moveBy(const Offset(-30, 0));
            await tester.pump(const Duration(milliseconds: 20));
            await gesture.moveBy(const Offset(-240, 0));
            await tester.pump(const Duration(milliseconds: 20));
            await gesture.up();
            await tester.pump();
          }
          expect(horizontal.page, greaterThan(0));
          expect(horizontal.page, lessThan(1));
          const center = Offset(320, 300);
          if (verticalInput == '휠') {
            await tester.sendEventToBinding(
              const PointerScrollEvent(
                position: center,
                scrollDelta: Offset(0, 400),
              ),
            );
          } else if (verticalInput == '터치') {
            final gesture = await tester.startGesture(center);
            await gesture.moveBy(const Offset(0, -30));
            await tester.pump(const Duration(milliseconds: 10));
            await gesture.moveBy(const Offset(0, -280));
            await tester.pump(const Duration(milliseconds: 10));
            await gesture.up();
          } else {
            final pointer = TestPointer(9, PointerDeviceKind.trackpad);
            await tester.sendEventToBinding(pointer.panZoomStart(center));
            await tester.sendEventToBinding(
              pointer.panZoomUpdate(center, pan: const Offset(0, -40)),
            );
            await tester.pump(const Duration(milliseconds: 10));
            await tester.sendEventToBinding(
              pointer.panZoomUpdate(center, pan: const Offset(0, -320)),
            );
            await tester.sendEventToBinding(pointer.panZoomEnd());
          }
          await tester.pump();
          expect(
            tester
                .widget<MealOfDaySwitchButton>(
                  find.byType(MealOfDaySwitchButton),
                )
                .label,
            '아침',
          );
          for (final view in tester.widgetList<NestedPageScrollView>(
            find.byType(NestedPageScrollView, skipOffstage: false),
          )) {
            if (view.controller.hasClients) expect(view.controller.page, 0);
          }
          await tester.pumpAndSettle();
          expect(horizontal.page, 1);
          expect(tab.index, 1);
          expect(
            tester
                .widget<MealOfDaySwitchButton>(
                  find.byType(MealOfDaySwitchButton),
                )
                .label,
            '아침',
          );
          // 정렬 완료 후에는 세로 입력이 정상적으로 다시 가능하다.
          await tester.sendEventToBinding(
            const PointerScrollEvent(
              position: center,
              scrollDelta: Offset(0, 400),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<MealOfDaySwitchButton>(
                  find.byType(MealOfDaySwitchButton),
                )
                .label,
            '점심',
          );
        },
      );
    }
  }

  testWidgets('먼 요일 클릭은 목적지 날짜를 즉시 표시하고 한 페이지 거리로 전환한다', (tester) async {
    await mount(tester);
    await tester.tap(find.text('화'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('토'));
    await tester.pump();
    expect(find.text('10월 10일'), findsOneWidget);
    final horizontal = tester
        .widgetList<PageView>(find.byType(PageView))
        .singleWhere((view) => view.scrollDirection == Axis.horizontal);
    expect(horizontal.controller!.page, closeTo(4, 0.01));
    await tester.pumpAndSettle();
    expect(horizontal.controller!.page, 5);
  });

  testWidgets('끼니 버튼 연속 클릭은 최신 목표를 유지하고 다른 요일에도 동기화한다', (tester) async {
    await mount(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(MealOfDaySwitchButton));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '아침',
    );
    await tester.tap(find.byType(MealOfDaySwitchButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('일'));
    await tester.pumpAndSettle();
    for (final view in tester.widgetList<NestedPageScrollView>(
      find.byType(NestedPageScrollView, skipOffstage: false),
    )) {
      if (view.controller.hasClients) expect(view.controller.page, 1);
    }
  });

  testWidgets('가로 휠은 요일만 이동하고 세로가 주성분이면 끼니만 이동한다', (tester) async {
    await mount(tester);
    final tabController = tester
        .widget<TabBar>(find.byType(TabBar))
        .controller!;
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 300),
        scrollDelta: Offset(400, 20),
      ),
    );
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(tabController.index, 1);
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '아침',
    );
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 300),
        scrollDelta: Offset(20, 400),
      ),
    );
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(tabController.index, 1);
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '점심',
    );
  });

  testWidgets('작은 가로 휠 입력을 합쳐 다음 요일로 넘긴다', (tester) async {
    await mount(tester);
    final tabController = tester
        .widget<TabBar>(find.byType(TabBar))
        .controller!;
    for (var i = 0; i < 3; i++) {
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 300),
          scrollDelta: Offset(40, 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tabController.index, 1);
  });

  testWidgets('연속 가로 입력 중에도 전환이 완료되고 관성으로 요일을 건너뛰지 않는다', (tester) async {
    await mount(tester);
    final tabController = tester
        .widget<TabBar>(find.byType(TabBar))
        .controller!;
    for (var i = 0; i < 20; i++) {
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(200, 300),
          scrollDelta: Offset(40, 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tabController.index, 1);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tabController.index, 1);
  });

  testWidgets('짧은 가로 입력은 저항을 보여주고 현재 요일로 복귀한다', (tester) async {
    await mount(tester);
    final horizontal = tester
        .widgetList<PageView>(find.byType(PageView))
        .singleWhere((view) => view.scrollDirection == Axis.horizontal);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 300),
        scrollDelta: Offset(40, 0),
      ),
    );
    await tester.pump();
    expect(horizontal.controller!.page, greaterThan(0));
    expect(horizontal.controller!.page, lessThan(40 / 400));
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(horizontal.controller!.page, 0);
  });

  testWidgets('가로 전환 애니메이션 중 반대 휠 입력을 받는다', (tester) async {
    await mount(tester);
    for (final delta in [100.0, -100.0]) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: const Offset(200, 300),
          scrollDelta: Offset(delta, 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 230));
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
  });

  testWidgets('Shift와 세로 휠 조합은 요일만 넘긴다', (tester) async {
    await mount(tester);
    final tabController = tester
        .widget<TabBar>(find.byType(TabBar))
        .controller!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      for (final kind in [
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      ]) {
        for (var i = 0; i < 3; i++) {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: kind,
              position: const Offset(200, 300),
              scrollDelta: kind == PointerDeviceKind.trackpad
                  ? const Offset(2, 40)
                  : const Offset(0, 40),
            ),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump(const Duration(milliseconds: 230));
        await tester.pumpAndSettle();
      }
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    expect(tabController.index, 2);
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '아침',
    );
  });
  testWidgets('가로 pan/zoom 트랙패드는 요일을 이동하고 끼니는 유지한다', (tester) async {
    await mount(tester);
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    const center = Offset(200, 300);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, pan: const Offset(-40, 5)),
    );
    await tester.pump();
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, pan: const Offset(-300, 10)),
    );
    await tester.pump();
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '아침',
    );
  });

  testWidgets('휠 페이지 이동 중 요일을 바꾸면 이전 요일의 종료 타이머를 취소한다', (tester) async {
    await mount(tester);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(200, 300),
        scrollDelta: Offset(0, 100),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('토'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 5);
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '아침',
    );
    expect(tester.takeException(), isNull);
  });
}
