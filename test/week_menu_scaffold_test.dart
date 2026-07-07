import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('cachedMealFuture 없이 mealFuture만으로 데이터를 렌더링한다', (tester) async {
    final weekMeal = WeekMeal.empty();
    weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory].add(
      const Meal([MealMenuItem(ko: '쌀밥')], 500),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          mealFuture: Future.value(weekMeal),
          appInfo: Future.value(_emptyAppInfo()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('쌀밥'), findsOneWidget);
  });

  testWidgets('bannerText가 있으면 상단에 배너를 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          mealFuture: Future.value(WeekMeal.empty()),
          appInfo: Future.value(_emptyAppInfo()),
          bannerText: '다음 주 미리보기 중',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('다음 주 미리보기 중'), findsOneWidget);
  });

  testWidgets('bannerText가 없으면 배너를 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          mealFuture: Future.value(WeekMeal.empty()),
          appInfo: Future.value(_emptyAppInfo()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('다음 주 미리보기 중'), findsNothing);
  });

  testWidgets('cachedMealFuture 데이터를 먼저 보여주고 mealFuture 완료 후 교체한다', (
    tester,
  ) async {
    final cachedWeekMeal = WeekMeal.empty();
    cachedWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory]
        .add(const Meal([MealMenuItem(ko: '캐시된 메뉴')], 100));
    final downloadedWeekMeal = WeekMeal.empty();
    downloadedWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory]
        .add(const Meal([MealMenuItem(ko: '새 메뉴')], 200));
    final downloadCompleter = Completer<WeekMeal>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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

  testWidgets('cachedMealFuture가 실패해도 mealFuture 데이터로 정상 렌더링한다', (tester) async {
    final downloadedWeekMeal = WeekMeal.empty();
    downloadedWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory]
        .add(const Meal([MealMenuItem(ko: '새 메뉴')], 200));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          cachedMealFuture: Future<WeekMeal>.error(
            Exception('no cache'),
          )..ignore(),
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WeekMenuScaffold(
          mondayOfWeek: DateTime(2026, 6, 22),
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          cachedMealFuture: Future<WeekMeal>.error(
            Exception('no cache'),
          )..ignore(),
          mealFuture: Future<WeekMeal>.error(
            Exception('network error'),
          )..ignore(),
          appInfo: Future.value(_emptyAppInfo()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Cannot load meal information.'), findsOneWidget);
  });
}
