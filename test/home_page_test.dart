import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/home_drawer.dart';
import 'package:meal_client/features/home/home_page.dart';
import 'package:meal_client/features/home/week_menu_scaffold.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('일요일 세션이 월요일에 재개되면 주간 화면 상태와 Future를 새로 만든다', (tester) async {
    var now = DateTime.utc(2026, 8, 16, 14, 30); // KST 일요일 23:30

    await tester.pumpWidget(_buildHomePage(() => now));
    final beforeResume = tester.widget<WeekMenuScaffold>(
      find.byType(WeekMenuScaffold),
    );

    now = DateTime.utc(2026, 8, 16, 15, 5); // KST 월요일 00:05
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final afterResume = tester.widget<WeekMenuScaffold>(
      find.byType(WeekMenuScaffold),
    );
    expect(afterResume.mondayOfWeek, DateTime.utc(2026, 8, 17));
    expect(afterResume.initialDayOfWeek, DayOfWeek.mon);
    expect(afterResume.initialMealOfDay, MealOfDay.breakfast);
    expect(afterResume.key, isNot(beforeResume.key));
    expect(
      afterResume.cachedMealFuture,
      isNot(same(beforeResume.cachedMealFuture)),
    );
    expect(afterResume.mealFuture, isNot(same(beforeResume.mealFuture)));
    expect(
      _nextWeekStart(afterResume),
      isNot(same(_nextWeekStart(beforeResume))),
    );
  });

  testWidgets('같은 KST 주에 재개되면 주간 화면 상태와 Future를 유지한다', (tester) async {
    var now = DateTime.utc(2026, 8, 16, 13, 30); // KST 일요일 22:30

    await tester.pumpWidget(_buildHomePage(() => now));
    final beforeResume = tester.widget<WeekMenuScaffold>(
      find.byType(WeekMenuScaffold),
    );

    now = DateTime.utc(2026, 8, 16, 14, 30); // KST 일요일 23:30
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    final afterResume = tester.widget<WeekMenuScaffold>(
      find.byType(WeekMenuScaffold),
    );
    expect(afterResume.key, beforeResume.key);
    expect(afterResume.cachedMealFuture, same(beforeResume.cachedMealFuture));
    expect(afterResume.mealFuture, same(beforeResume.mealFuture));
    expect(_nextWeekStart(afterResume), same(_nextWeekStart(beforeResume)));
  });

  testWidgets('월요일 갱신은 지연된 일요일 갱신 뒤에도 새 주 결과를 유지한다', (tester) async {
    var now = DateTime.utc(2026, 8, 16, 14, 30); // KST 일요일 23:30
    final sundayCache = Completer<MealResponse>();
    final sundayRefresh = Completer<MealResponse>();
    final mondayRefresh = Completer<MealResponse>();
    final sundayWidgetRefresh = Completer<void>();
    final sundayResponse = _mealResponse(DateTime.utc(2026, 8, 10));
    final mondayResponse = _mealResponse(DateTime.utc(2026, 8, 17));
    var firstCacheLoad = true;
    var firstRefresh = true;
    final sundayRefreshStarted = Completer<void>();
    final mondayRefreshStarted = Completer<void>();
    final sundayWidgetRefreshStarted = Completer<void>();
    var widgetRefreshCount = 0;

    await tester.pumpWidget(
      _buildHomePage(
        () => now,
        loadCachedMeal: () {
          if (firstCacheLoad) {
            firstCacheLoad = false;
            return sundayCache.future;
          }
          return Future.value(mondayResponse);
        },
        refreshMeal: () {
          if (firstRefresh) {
            firstRefresh = false;
            sundayRefreshStarted.complete();
            return sundayRefresh.future;
          }
          mondayRefreshStarted.complete();
          return mondayRefresh.future;
        },
        refreshHomeWidgets: () {
          widgetRefreshCount++;
          if (widgetRefreshCount == 2) {
            sundayWidgetRefreshStarted.complete();
            return sundayWidgetRefresh.future;
          }
          return Future.value();
        },
      ),
    );

    now = DateTime.utc(2026, 8, 16, 15, 5); // KST 월요일 00:05
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final mondayScaffold = tester.widget<WeekMenuScaffold>(
      find.byType(WeekMenuScaffold),
    );

    sundayCache.complete(sundayResponse);
    await sundayRefreshStarted.future;

    sundayRefresh.complete(sundayResponse);
    await sundayWidgetRefreshStarted.future;

    sundayWidgetRefresh.complete();
    await mondayRefreshStarted.future;

    mondayRefresh.complete(mondayResponse);
    await tester.pumpAndSettle();
    expect(await mondayScaffold.mealFuture, same(mondayResponse.weekMeal));
  });

  testWidgets('늦게 저장된 info cache도 후속 위젯 render를 요청한다', (tester) async {
    final info = Completer<AppInfo>();
    var widgetRefreshCount = 0;

    await tester.pumpWidget(
      _buildHomePage(
        () => DateTime.utc(2026, 8, 10),
        loadAppInfo: () => info.future,
        refreshHomeWidgets: () async => widgetRefreshCount++,
      ),
    );
    await tester.pump();
    expect(widgetRefreshCount, 1);

    info.complete(await _loadEmptyAppInfo());
    await tester.pump();
    expect(widgetRefreshCount, 2);
  });

  testWidgets('info 갱신 실패는 meal cache의 위젯 render를 막지 않는다', (tester) async {
    var widgetRefreshCount = 0;

    await tester.pumpWidget(
      _buildHomePage(
        () => DateTime.utc(2026, 8, 10),
        loadAppInfo: () async => throw Exception('info failed'),
        refreshHomeWidgets: () async => widgetRefreshCount++,
      ),
    );
    await tester.pump();

    expect(widgetRefreshCount, 1);
  });
}

Future<String?>? _nextWeekStart(WeekMenuScaffold scaffold) {
  return (scaffold.drawer! as HomePageDrawer).nextWeekStart;
}

Widget _buildHomePage(
  DateTime Function() now, {
  Future<AppInfo> Function()? loadAppInfo,
  Future<MealResponse> Function()? loadCachedMeal,
  Future<MealResponse> Function()? refreshMeal,
  Future<void> Function()? refreshHomeWidgets,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: HomePage(
      now: now,
      loadAppInfo: loadAppInfo ?? _loadEmptyAppInfo,
      loadCachedMeal:
          loadCachedMeal ??
          () async => _mealResponse(DateTime.utc(2026, 8, 10)),
      refreshMeal:
          refreshMeal ?? () async => _mealResponse(DateTime.utc(2026, 8, 10)),
      refreshHomeWidgets: refreshHomeWidgets ?? () async {},
    ),
  );
}

Future<AppInfo> _loadEmptyAppInfo() async {
  return AppInfo.fromJson({
    'announcement': null,
    'operatingHours': {
      'weekday': <String, dynamic>{},
      'weekend': <String, dynamic>{},
    },
  });
}

MealResponse _mealResponse(DateTime startDate) {
  return (
    weekMeal: WeekMeal.empty(),
    weekMeta: WeekMeta(
      startDate: startDate,
      isCurrentWeek: true,
      nextWeekStart: null,
    ),
  );
}
