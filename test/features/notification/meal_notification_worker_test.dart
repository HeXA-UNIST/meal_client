import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/notification/meal_alert_period.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';

void main() {
  group('notification background cache refresh', () {
    test('meal cache refresh가 성공하면 info fetch 실패만으로 task를 실패시키지 않음', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async => throw Exception('info unavailable'),
        refreshWidget: () async {},
      );

      expect(result, isTrue);
    });

    test('meal cache refresh 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async => throw Exception('meal unavailable'),
        refreshInfoCache: () async {},
        refreshWidget: () async {},
      );

      expect(result, isFalse);
    });

    test('info cache write 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async =>
            throw InfoCacheWriteException(Exception('disk full')),
        refreshWidget: () async {},
      );

      expect(result, isFalse);
    });

    test('meal과 info cache refresh를 병렬로 시작', () async {
      var mealCompleted = false;
      var infoStartedBeforeMealCompleted = false;

      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          mealCompleted = true;
        },
        refreshInfoCache: () async {
          infoStartedBeforeMealCompleted = !mealCompleted;
        },
        refreshWidget: () async {},
      );

      expect(result, isTrue);
      expect(infoStartedBeforeMealCompleted, isTrue);
    });

    test('widget refresh 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async {},
        refreshWidget: () async => throw Exception('widget unavailable'),
      );

      expect(result, isFalse);
    });
  });

  group('알림 메뉴 대상 요일', () {
    test('밤 알림은 다음 날 아침 메뉴의 요일을 사용한다', () {
      final thursdayNight = DateTime(2026, 7, 16, 21, 30);

      expect(
        notificationTargetDayFor(MealAlertPeriod.night, thursdayNight),
        DayOfWeek.fri,
      );
    });

    test('오늘 식사 알림은 실행 당일의 요일을 사용한다', () {
      final thursdayLunch = DateTime(2026, 7, 16, 11);

      expect(
        notificationTargetDayFor(MealAlertPeriod.lunch, thursdayLunch),
        DayOfWeek.thu,
      );
    });
  });

  group('알림 키워드 매칭', () {
    final meal = Meal(
      sections: const [
        MealSection(
          type: MealSectionType.regular,
          menu: [MealMenuItem(ko: '떡갈비', en: 'Grilled Short Rib Patties')],
        ),
        MealSection(
          type: MealSectionType.convenience,
          menu: [MealMenuItem(ko: '참치마요 덮밥')],
        ),
        MealSection(
          type: MealSectionType.special,
          menu: [MealMenuItem(ko: '특선 메뉴', en: 'Chef Special')],
        ),
        MealSection(
          type: MealSectionType.salad,
          menu: [MealMenuItem(ko: '시저 샐러드', en: 'Caesar Salad')],
        ),
      ],
    );

    test('표시 대상 섹션의 한글과 영문 메뉴를 대소문자 구분 없이 검색한다', () {
      expect(mealContainsKeyword(meal, '떡갈비'), isTrue);
      expect(mealContainsKeyword(meal, 'grilled short'), isTrue);
      expect(mealContainsKeyword(meal, '참치마요'), isTrue);
      expect(mealContainsKeyword(meal, 'chef special'), isTrue);
    });

    test('표시하지 않는 SALAD 섹션은 검색 대상에서 제외한다', () {
      expect(mealContainsKeyword(meal, '시저'), isFalse);
      expect(mealContainsKeyword(meal, 'caesar'), isFalse);
    });
  });
}
