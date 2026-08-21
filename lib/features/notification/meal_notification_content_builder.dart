import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'meal_notification_period.dart';

typedef MealNotificationContent = ({int id, String title, String body});
typedef _NotificationMealGroup = ({int id, List<Meal> meals});

/// 선택된 식당의 전체 메뉴 또는 Debug 키워드 매칭 결과를 알림 콘텐츠로 만든다.
List<MealNotificationContent> buildMealNotificationContents({
  required WeekMeal weekMeal,
  required DateTime targetDate,
  required MealNotificationPeriod period,
  required NotificationDeliverySettings settings,
  required AppLocalizations l10n,
}) {
  final mealsByLabel = <String, _NotificationMealGroup>{};
  for (final cafeteria in Cafeteria.values.where(
    settings.cafeterias.contains,
  )) {
    final meals = mealsForNotificationTarget(
      weekMeal: weekMeal,
      targetDate: targetDate,
      period: period,
      cafeteria: cafeteria,
    );
    for (final meal in meals) {
      final String label;
      final int notificationId;
      if (cafeteria == Cafeteria.dormitory) {
        if (meal is KoreanMeal) {
          if (!settings.dormMealTypes.contains(DormMealType.korean)) continue;
          label = l10n.cafeteriaWithMealType(
            l10n.dormitoryCafeteria,
            l10n.menuKorean,
          );
          notificationId = 1;
        } else if (meal is HalalMeal) {
          if (!settings.dormMealTypes.contains(DormMealType.halal)) continue;
          label = l10n.cafeteriaWithMealType(
            l10n.dormitoryCafeteria,
            l10n.menuHalal,
          );
          notificationId = 2;
        } else {
          // 기숙사 알림 설정은 한식과 할랄만 지원한다.
          continue;
        }
      } else {
        label = switch (cafeteria) {
          Cafeteria.dormitory => l10n.dormitoryCafeteria, // unreachable
          Cafeteria.student => l10n.studentCafeteria,
          Cafeteria.faculty => l10n.facultyCafeteria,
        };
        notificationId = switch (cafeteria) {
          Cafeteria.dormitory => 0, // unreachable
          Cafeteria.student => 3,
          Cafeteria.faculty => 4,
        };
      }
      mealsByLabel
          .putIfAbsent(label, () => (id: notificationId, meals: <Meal>[]))
          .meals
          .add(meal);
    }
  }

  final keywords = settings.keywords;
  final periodLabel = _periodLabel(period, l10n);
  if (keywords.isEmpty) {
    final contents = <MealNotificationContent>[];
    for (final entry in mealsByLabel.entries) {
      final items = <String>{
        for (final meal in entry.value.meals)
          ..._notificationMenuItems(meal, l10n.localeName),
      }.toList(growable: false);
      if (items.isEmpty) continue;
      contents.add((
        id: entry.value.id,
        title: l10n.mealNotificationTitle(
          entry.key,
          _mealOfDayLabel(period, l10n),
        ),
        body: items.join(' / '),
      ));
    }
    return contents;
  }

  final matchesByKeyword = <String, List<String>>{};
  for (final keyword in keywords) {
    final keywordLower = keyword.toLowerCase();
    final matches = <String>[];
    for (final entry in mealsByLabel.entries) {
      if (entry.value.meals.any(
        (meal) => mealContainsKeyword(meal, keywordLower),
      )) {
        matches.add(entry.key);
      }
    }
    if (matches.isNotEmpty) matchesByKeyword[keyword] = matches;
  }

  if (matchesByKeyword.isEmpty) return const [];

  final String title;
  final String body;
  if (matchesByKeyword.length == 1) {
    final entry = matchesByKeyword.entries.first;
    title = l10n.keywordMealNotificationTitle(periodLabel, entry.key);
    body = entry.value.join(', ');
  } else {
    title = l10n.multipleKeywordMealNotificationTitle(periodLabel);
    body = matchesByKeyword.entries
        .map((entry) => '"${entry.key}": ${entry.value.join(', ')}')
        .join('\n');
  }

  return [(id: 9, title: title, body: body)];
}

Iterable<String> _notificationMenuItems(Meal meal, String languageCode) => meal
    .sections
    .where((section) => section.type != MealSectionType.salad)
    .expand((section) => section.menu)
    .map((item) => item.textFor(languageCode).trim())
    .where((item) => item.isNotEmpty);

/// 주차 조회 결과에서 저장된 메뉴 대상 날짜의 식단만 꺼낸다.
List<Meal> mealsForNotificationTarget({
  required WeekMeal weekMeal,
  required DateTime targetDate,
  required MealNotificationPeriod period,
  required Cafeteria cafeteria,
}) {
  final targetDay = DayOfWeek.values[targetDate.weekday - 1];
  return weekMeal[targetDay][period.mealOfDay][cafeteria];
}

/// 알림 대상 섹션의 한글/영문 메뉴에서 소문자 키워드를 찾는다.
bool mealContainsKeyword(Meal meal, String keywordLower) {
  return meal.sections
      .where((section) => section.type != MealSectionType.salad)
      .expand((section) => section.menu)
      .any(
        (item) =>
            item.ko.toLowerCase().contains(keywordLower) ||
            (item.en?.toLowerCase().contains(keywordLower) ?? false),
      );
}

String _periodLabel(MealNotificationPeriod period, AppLocalizations l10n) =>
    switch (period) {
      MealNotificationPeriod.morning => l10n.notificationTodayBreakfast,
      MealNotificationPeriod.lunch => l10n.notificationTodayLunch,
      MealNotificationPeriod.dinner => l10n.notificationTodayDinner,
      MealNotificationPeriod.night => l10n.notificationTomorrowBreakfast,
    };

String _mealOfDayLabel(MealNotificationPeriod period, AppLocalizations l10n) =>
    switch (period) {
      MealNotificationPeriod.morning ||
      MealNotificationPeriod.night => l10n.breakfast,
      MealNotificationPeriod.lunch => l10n.lunch,
      MealNotificationPeriod.dinner => l10n.dinner,
    };
