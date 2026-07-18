import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/enum_utils.dart';
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
        MealTimeConfig.toKst(expected),
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

  group('NotificationScheduleCoordinator', () {
    test('연속된 예약 요청은 마지막 설정만 실행한다', () async {
      final scheduledDays = <Set<DayOfWeek>>[];
      final coordinator = NotificationScheduleCoordinator(
        debounce: Duration.zero,
        schedule: (_, days) async => scheduledDays.add(days),
      );

      final first = coordinator.schedule({}, {DayOfWeek.mon});
      final latest = coordinator.schedule({}, {DayOfWeek.fri});

      expect(await first, NotificationScheduleOutcome.superseded);
      expect(await latest, NotificationScheduleOutcome.scheduled);
      expect(scheduledDays, [
        {DayOfWeek.fri},
      ]);
    });

    test('진행 중인 예약 뒤에 취소 작업을 순서대로 실행한다', () async {
      final events = <String>[];
      final scheduleStarted = Completer<void>();
      final releaseSchedule = Completer<void>();
      final coordinator = NotificationScheduleCoordinator(
        debounce: Duration.zero,
        schedule: (_, _) async {
          events.add('schedule');
          scheduleStarted.complete();
          await releaseSchedule.future;
        },
        cancel: () async => events.add('cancel'),
      );

      final scheduled = coordinator.schedule({}, {DayOfWeek.mon});
      await scheduleStarted.future;
      final canceled = coordinator.cancelAll();
      releaseSchedule.complete();

      await scheduled;
      await canceled;

      expect(events, ['schedule', 'cancel']);
    });

    test('dispose하면 보류 중인 예약을 실행하지 않는다', () async {
      var scheduleCount = 0;
      final coordinator = NotificationScheduleCoordinator(
        debounce: const Duration(milliseconds: 10),
        schedule: (_, _) async => scheduleCount++,
      );

      final scheduled = coordinator.schedule({}, {DayOfWeek.mon});
      coordinator.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(scheduleCount, isZero);
      expect(await scheduled, NotificationScheduleOutcome.disposed);
    });

    test('예약 콜백 실패를 반환 Future에 전달한다', () async {
      final coordinator = NotificationScheduleCoordinator(
        debounce: Duration.zero,
        schedule: (_, _) async => throw StateError('schedule failed'),
      );

      await expectLater(
        coordinator.schedule({}, {DayOfWeek.mon}),
        throwsStateError,
      );
    });

    test('즉시 예약은 디바운스를 기다리지 않는다', () async {
      var scheduleCount = 0;
      final coordinator = NotificationScheduleCoordinator(
        debounce: const Duration(days: 1),
        schedule: (_, _) async => scheduleCount++,
      );

      final outcome = await coordinator.scheduleNow({}, {DayOfWeek.mon});

      expect(outcome, NotificationScheduleOutcome.scheduled);
      expect(scheduleCount, 1);
    });
  });

  group('notificationDaysFromNames', () {
    test('저장값이 없으면 모든 요일을 사용한다', () {
      expect(notificationDaysFromNames(null), DayOfWeek.values.toSet());
    });

    test('알 수 없는 저장값은 무시한다', () {
      expect(notificationDaysFromNames(['mon', 'unknown', 'fri']), {
        DayOfWeek.mon,
        DayOfWeek.fri,
      });
    });

    test('다른 enum도 유효한 이름만 변환한다', () {
      expect(enumSetFromNames(['dormitory', 'invalid'], Cafeteria.values), {
        Cafeteria.dormitory,
      });
    });
  });
}
