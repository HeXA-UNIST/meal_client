import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:meal_client/features/home/menu_header_region.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/week_menu_scaffold.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';

AppInfo _emptyAppInfo() => AppInfo.fromJson({
  'announcement': null,
  'operatingHours': {
    'weekday': <String, dynamic>{},
    'weekend': <String, dynamic>{},
  },
});

void main() {
  testWidgets('상단 오른쪽 예약 영역은 첫 줄만 줄이고 창이 바뀌면 기본 헤더로 돌아간다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(669, 951);
    tester.view.padding = const FakeViewPadding(top: 84);
    addTearDown(tester.view.reset);
    final region = ValueNotifier<MenuHeaderRegion?>(
      const MenuHeaderRegion(
        Size(669, 951),
        84,
        Rect.fromLTWH(14, 20, 526, 52),
      ),
    );
    addTearDown(region.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MenuHeaderRegion?>(
        valueListenable: region,
        builder: (_, value, child) =>
            Provider<MenuHeaderRegion?>.value(value: value, child: child),
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: WeekMenuScaffold(
            mondayOfWeek: DateTime(2026, 6, 22),
            initialDayOfWeek: DayOfWeek.mon,
            initialMealOfDay: MealOfDay.breakfast,
            mealFuture: Future.value(WeekMeal.empty()),
            appInfo: Future.value(_emptyAppInfo()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(TextButton, '아침');
    final tabs = find.byType(TabBar);
    expect(tester.getCenter(button).dy, 46);
    expect(tester.getTopLeft(find.byType(AppBar)).dx, 14);
    expect(tester.getTopRight(button).dx, lessThanOrEqualTo(540));
    expect(tester.getTopRight(tabs).dx, greaterThan(540));
    expect(tester.getTopLeft(tabs).dy, 84);
    region.value = const MenuHeaderRegion(
      Size(669, 951),
      84,
      Rect.fromLTWH(22, 22, 458, 52),
    );
    await tester.pump();
    expect(tester.getTopRight(button).dx, lessThanOrEqualTo(480));
    tester.view.physicalSize = const Size(620, 951);
    await tester.pump();
    expect(tester.getTopLeft(button).dy, greaterThanOrEqualTo(84));
    region.value = null;
    tester.view.physicalSize = const Size(669, 951);
    await tester.pump();
    expect(tester.getTopLeft(tabs).dy, 84 + MenuHeaderRegion.toolbarHeight);
  });

  testWidgets('로딩 중 선택한 끼니를 데이터 도착 후에도 유지한다', (tester) async {
    final response = Completer<WeekMeal>();
    final week = WeekMeal.empty();
    for (final (meal, text) in [
      (MealOfDay.breakfast, '아침 데이터'),
      (MealOfDay.lunch, '점심 데이터'),
    ]) {
      week[DayOfWeek.mon][meal][Cafeteria.dormitory].add(
        Meal.regular(menu: [MealMenuItem(ko: text)]),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          mealFuture: response.future,
          appInfo: Future.value(_emptyAppInfo()),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('아침'));
    await tester.pump();
    response.complete(week);
    await tester.pumpAndSettle();
    expect(find.text('점심'), findsOneWidget);
    expect(find.text('점심 데이터'), findsOneWidget);
    expect(find.text('아침 데이터'), findsNothing);
  });

  testWidgets('cachedMealFuture 데이터를 먼저 보여주고 mealFuture 완료 후 교체한다', (
    tester,
  ) async {
    final cachedWeekMeal = WeekMeal.empty();
    cachedWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory].add(
      Meal.regular(menu: const [MealMenuItem(ko: '캐시된 메뉴')], kcal: 100),
    );
    final downloadedWeekMeal = WeekMeal.empty();
    downloadedWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory]
        .add(Meal.regular(menu: const [MealMenuItem(ko: '새 메뉴')], kcal: 200));
    final downloadCompleter = Completer<WeekMeal>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          cachedMealFuture: Future.value(cachedWeekMeal),
          mealFuture: downloadCompleter.future,
          appInfo: Future.value(_emptyAppInfo()),
        ),
      ),
    );

    // downloadCompleter는 아직 완료되지 않았지만, 이 시점엔 cachedMealFuture가
    // 이미 해소되어 TabBarView가 표시되므로 화면에 무한 반복 애니메이션(예:
    // CircularProgressIndicator) 위젯이 없다. 따라서 pumpAndSettle을 써도
    // 안전하게(타임아웃 없이) 안정 상태에 도달한다.
    await tester.pumpAndSettle();
    expect(find.text('캐시된 메뉴'), findsOneWidget);
    expect(find.text('새 메뉴'), findsNothing);

    downloadCompleter.complete(downloadedWeekMeal);
    await tester.pumpAndSettle();

    expect(find.text('새 메뉴'), findsOneWidget);
    expect(find.text('캐시된 메뉴'), findsNothing);
  });

  testWidgets('cachedMealFuture가 실패해도 mealFuture 데이터로 정상 렌더링한다', (
    tester,
  ) async {
    final downloadedWeekMeal = WeekMeal.empty();
    downloadedWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory]
        .add(Meal.regular(menu: const [MealMenuItem(ko: '새 메뉴')], kcal: 200));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          cachedMealFuture: Future<WeekMeal>.error(Exception('no cache'))
            ..ignore(),
          mealFuture: Future.value(downloadedWeekMeal),
          appInfo: Future.value(_emptyAppInfo()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('새 메뉴'), findsOneWidget);
  });

  testWidgets('cachedMealFuture와 mealFuture 모두 실패하면 에러 메시지를 보여준다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          cachedMealFuture: Future<WeekMeal>.error(Exception('no cache'))
            ..ignore(),
          mealFuture: Future<WeekMeal>.error(Exception('network error'))
            ..ignore(),
          appInfo: Future.value(_emptyAppInfo()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Cannot load meal information.'), findsOneWidget);
  });
}
