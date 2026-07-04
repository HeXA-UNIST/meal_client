import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/nested_page_scroll.dart';
import 'package:meal_client/features/home/week_meal_view.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
  testWidgets('식단 카드에 선택한 요일과 끼니의 운영시간을 전달한다', (tester) async {
    final weekMeal = WeekMeal.empty();
    weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory].add(
      const Meal([MealMenuItem(ko: '쌀밥')], 935),
    );

    final tabController = TabController(length: 7, vsync: tester);
    final pageControllerGroup = NestedPageScrollControllerGroup(
      count: DayOfWeek.values.length,
      pageCount: MealOfDay.values.length,
    );
    addTearDown(tabController.dispose);
    addTearDown(pageControllerGroup.dispose);

    final appInfo = AppInfo.fromJson(
      jsonDecode(
            jsonEncode({
              'announcement': null,
              'operatingHours': {
                'weekday': {
                  'dormitory': {
                    'breakfast': {'start': '08:00', 'end': '09:20'},
                  },
                },
                'weekend': {},
              },
            }),
          )
          as Map<String, dynamic>,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WeekMealTabBarView(
            weekMeal: weekMeal,
            tabController: tabController,
            pageControllerGroup: pageControllerGroup,
            pageCount: MealOfDay.values.length,
            onPageChanged: (_) {},
            appInfo: Future.value(appInfo),
            mondayOfWeek: DateTime(2026, 6, 15),
            currentKstDateTime: DateTime(2026, 6, 15, 8, 30),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('08:00 - 09:20'),
      ),
      findsOneWidget,
    );
  });
}
