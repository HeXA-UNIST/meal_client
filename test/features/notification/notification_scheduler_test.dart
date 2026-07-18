import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_alert_period.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';

void main() {
  group('nextEnabledFireTime', () {
    test('밤 알림은 KST 메뉴 대상 요일이 선택된 경우 오늘 밤으로 예약한다', () {
      final now = DateTime(2026, 7, 16, 20);
      final expected = DateTime(2026, 7, 16, 21, 30);
      final targetDay = notificationTargetDayFor(
        MealAlertPeriod.night,
        expected.toUtc().add(const Duration(hours: 9)),
      );

      final result = nextEnabledFireTime(
        period: MealAlertPeriod.night,
        alertTime: const TimeOfDay(hour: 21, minute: 30),
        enabledDays: {targetDay},
        now: now,
      );

      expect(result, expected);
    });

    test('선택되지 않은 메뉴 요일은 건너뛰고 다음 활성 요일로 예약한다', () {
      final now = DateTime(2026, 7, 16, 10); // 목요일

      final result = nextEnabledFireTime(
        period: MealAlertPeriod.lunch,
        alertTime: const TimeOfDay(hour: 11, minute: 0),
        enabledDays: {DayOfWeek.mon},
        now: now,
      );

      expect(result, DateTime(2026, 7, 20, 11));
    });

    test('예약 시각이 지났으면 다음 활성 메뉴 요일을 찾는다', () {
      final now = DateTime(2026, 7, 16, 11);

      final result = nextEnabledFireTime(
        period: MealAlertPeriod.lunch,
        alertTime: const TimeOfDay(hour: 11, minute: 0),
        enabledDays: {DayOfWeek.thu},
        now: now,
      );

      expect(result, DateTime(2026, 7, 23, 11));
    });

    test('선택된 요일이 없으면 예약할 시각이 없다', () {
      final result = nextEnabledFireTime(
        period: MealAlertPeriod.lunch,
        alertTime: const TimeOfDay(hour: 11, minute: 0),
        enabledDays: {},
        now: DateTime(2026, 7, 16, 10),
      );

      expect(result, isNull);
    });
  });
}
