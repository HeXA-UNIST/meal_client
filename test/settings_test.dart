import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/meal.dart';
import 'package:meal_client/settings/allergy_settings.dart';
import 'package:meal_client/settings/notification_settings.dart';
import 'package:meal_client/settings/widget_settings.dart';

void main() {
  group('AllergySettings', () {
    test('기본값: enabledIds가 비어 있음', () {
      final s = AllergySettings();
      expect(s.enabledIds, isEmpty);
    });

    test('toggle — 없는 ID 추가', () {
      final s = AllergySettings();
      final next = s.toggle(1);
      expect(next.enabledIds, contains(1));
    });

    test('toggle — 있는 ID 제거', () {
      final s = AllergySettings(enabledIds: {1, 2});
      final next = s.toggle(1);
      expect(next.enabledIds, isNot(contains(1)));
      expect(next.enabledIds, contains(2));
    });

    test('reset — enabledIds가 비어 있음', () {
      final s = AllergySettings(enabledIds: {1, 5, 9});
      expect(s.reset().enabledIds, isEmpty);
    });

    test('enabledIds — 불변 Set 반환', () {
      final s = AllergySettings(enabledIds: {1, 2});
      expect(() => (s.enabledIds as dynamic).add(3), throwsUnsupportedError);
    });
  });

  group('NotificationSettings', () {
    test('기본값', () {
      final s = NotificationSettings();
      expect(s.enabled, isFalse);
      expect(s.keyword, isEmpty);
      expect(s.alertTime, const TimeOfDay(hour: 8, minute: 0));
      expect(s.cafeterias, equals({Cafeteria.dormitory}));
    });

    test('copyWith — enabled만 변경', () {
      final s = NotificationSettings();
      final next = s.copyWith(enabled: true);
      expect(next.enabled, isTrue);
      expect(next.keyword, isEmpty);
    });

    test('copyWith — keyword 빈 문자열로 초기화', () {
      final s = NotificationSettings(keyword: '돈까스');
      final next = s.copyWith(keyword: '');
      expect(next.keyword, isEmpty);
    });

    test('reset — 기본값으로 초기화', () {
      final s = NotificationSettings(enabled: true, keyword: '돈까스');
      final r = s.reset();
      expect(r.enabled, isFalse);
      expect(r.keyword, isEmpty);
    });

    test('cafeterias — 불변 Set 반환', () {
      final s = NotificationSettings();
      expect(
        () => (s.cafeterias as dynamic).add(Cafeteria.student),
        throwsUnsupportedError,
      );
    });
  });

  group('WidgetSettings', () {
    test('기본값', () {
      const s = WidgetSettings();
      expect(s.cafeteria, Cafeteria.dormitory);
      expect(s.mealOfDay, MealOfDay.lunch);
    });

    test('copyWith', () {
      const s = WidgetSettings();
      final next = s.copyWith(cafeteria: Cafeteria.student);
      expect(next.cafeteria, Cafeteria.student);
      expect(next.mealOfDay, MealOfDay.lunch);
    });
  });
}
