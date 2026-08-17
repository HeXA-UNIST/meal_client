import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/nested_page_scroll.dart';
import 'package:meal_client/features/home/week_meal_view.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
  test('공유 텍스트는 카드와 같은 섹션 순서와 제목을 사용한다', () {
    const meal = Meal(
      sections: [
        MealSection(
          type: MealSectionType.regular,
          title: MealSectionTitle(ko: '천원의 아침밥'),
          menu: [MealMenuItem(ko: '쌀밥')],
          kcal: 700,
        ),
        MealSection(
          type: MealSectionType.convenience,
          menu: [MealMenuItem(ko: '삼각김밥')],
        ),
      ],
    );

    expect(
      buildMealShareText(
        cardTitle: '기숙사 식당 한식',
        meal: meal,
        languageCode: 'ko',
        convenienceLabel: '간편식',
        specialLabel: '특별식',
      ),
      '[기숙사 식당 한식]\n\n[천원의 아침밥]\n- 쌀밥\n\n[간편식]\n- 삼각김밥\n\n700 kcal',
    );
  });

  testWidgets('식단 카드에 선택한 요일과 끼니의 운영시간을 전달한다', (tester) async {
    final weekMeal = WeekMeal.empty();
    weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory].add(
      Meal.regular(menu: const [MealMenuItem(ko: '쌀밥')], kcal: 935),
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

  testWidgets('운영시간과 칼로리 유무가 달라도 모든 카드에 같은 메타데이터 배율을 적용한다', (tester) async {
    tester.view.physicalSize = const Size(330, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final weekMeal = WeekMeal.empty();
    weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory]
      ..add(Meal.regular(menu: const [MealMenuItem(ko: '쌀밥')], kcal: 935))
      ..add(Meal.regular(menu: const [MealMenuItem(ko: '죽')]));

    final tabController = TabController(length: 7, vsync: tester);
    final pageControllerGroup = NestedPageScrollControllerGroup(
      count: DayOfWeek.values.length,
      pageCount: MealOfDay.values.length,
    );
    addTearDown(tabController.dispose);
    addTearDown(pageControllerGroup.dispose);

    final appInfo = AppInfo.fromJson({
      'announcement': null,
      'operatingHours': {
        'weekday': {
          'dormitory': {
            'breakfast': {'start': '06:00', 'end': '08:00'},
          },
        },
        'weekend': <String, dynamic>{},
      },
    });

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
            currentKstDateTime: DateTime(2026, 6, 15, 7),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final timeTexts = tester.widgetList<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('06:00 - 08:00'),
      ),
    );
    final fontSizes = timeTexts
        .map((text) => (text.text as TextSpan).style!.fontSize)
        .toList(growable: false);

    expect(fontSizes, hasLength(2));
    expect(fontSizes[0], fontSizes[1]);
    expect(fontSizes[0], lessThan(11));
  });
}
