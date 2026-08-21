import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/enum_utils.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';

void main() {
  group('nextEnabledFireTime', () {
    test('밤 알림은 월요일 아침이 활성화됐을 때 일요일 밤으로 예약한다', () {
      final now = DateTime(2026, 7, 19, 20);
      final expected = DateTime(2026, 7, 19, 21, 30);

      final result = nextEnabledFireTime(
        period: MealNotificationPeriod.night,
        alertTime: const TimeOfDay(hour: 21, minute: 30),
        enabledDays: {DayOfWeek.mon},
        now: now,
      );

      expect(result, expected);
    });

    test('월요일 아침이 비활성화되면 일요일 밤에는 예약하지 않는다', () {
      final result = nextEnabledFireTime(
        period: MealNotificationPeriod.night,
        alertTime: const TimeOfDay(hour: 21, minute: 30),
        enabledDays: {DayOfWeek.fri},
        now: DateTime(2026, 7, 19, 20),
      );

      expect(result, DateTime(2026, 7, 23, 21, 30));
    });

    test('선택되지 않은 메뉴 요일은 건너뛰고 다음 활성 요일로 예약한다', () {
      final now = DateTime(2026, 7, 16, 10); // 목요일

      final result = nextEnabledFireTime(
        period: MealNotificationPeriod.lunch,
        alertTime: const TimeOfDay(hour: 11, minute: 0),
        enabledDays: {DayOfWeek.mon},
        now: now,
      );

      expect(result, DateTime(2026, 7, 20, 11));
    });

    test('예약 시각이 지났으면 다음 활성 메뉴 요일을 찾는다', () {
      final now = DateTime(2026, 7, 16, 11);

      final result = nextEnabledFireTime(
        period: MealNotificationPeriod.lunch,
        alertTime: const TimeOfDay(hour: 11, minute: 0),
        enabledDays: {DayOfWeek.thu},
        now: now,
      );

      expect(result, DateTime(2026, 7, 23, 11));
    });

    test('선택된 요일이 없으면 예약할 시각이 없다', () {
      final result = nextEnabledFireTime(
        period: MealNotificationPeriod.lunch,
        alertTime: const TimeOfDay(hour: 11, minute: 0),
        enabledDays: {},
        now: DateTime(2026, 7, 16, 10),
      );

      expect(result, isNull);
    });
  });

  group('알림 대상 날짜', () {
    test('일요일 밤은 다음 주 월요일 아침을 대상으로 한다', () {
      final sundayNight = DateTime.utc(2026, 7, 19, 12, 30);

      expect(
        notificationTargetDateFor(MealNotificationPeriod.night, sundayNight),
        DateTime.utc(2026, 7, 20),
      );
      expect(
        kstWeekStartFromDate(
          notificationTargetDateFor(MealNotificationPeriod.night, sundayNight),
        ),
        DateTime.utc(2026, 7, 20),
      );
    });

    test('KST가 아닌 기기 시간대에서도 KST 달력 날짜를 사용한다', () {
      final deviceTime = DateTime.parse('2026-07-19T17:30:00-07:00');

      expect(kstCalendarDate(deviceTime), DateTime.utc(2026, 7, 20));
    });

    test('저장한 대상 날짜는 UTC 날짜값으로만 파싱한다', () {
      expect(
        notificationTargetDateFromString('2026-07-20'),
        DateTime.utc(2026, 7, 20),
      );
      expect(notificationTargetDateFromString('2026-02-30'), isNull);
      expect(notificationTargetDateFromString('2026/07/20'), isNull);
    });
  });

  group('Workmanager 예약 등록', () {
    test('일요일 밤 예약은 다음 월요일 대상 날짜를 입력값으로 저장한다', () async {
      Map<String, dynamic>? capturedInputData;

      await scheduleKeywordNotificationFor(
        MealNotificationPeriod.night,
        const TimeOfDay(hour: 21, minute: 30),
        {DayOfWeek.mon},
        nowProvider: () => DateTime(2026, 7, 19, 20),
        cancelTask: (_) async {},
        registerTask:
            ({
              required uniqueName,
              required taskName,
              required initialDelay,
              required inputData,
            }) async {
              capturedInputData = inputData;
            },
      );

      expect(capturedInputData, {'targetDate': '2026-07-20'});
    });
  });

  group('NotificationScheduleCoordinator', () {
    test('연속된 예약 요청은 마지막 설정만 실행한다', () async {
      final scheduledDays = <Set<DayOfWeek>>[];
      final coordinator = NotificationScheduleCoordinator(
        debounce: Duration.zero,
        schedule: (settings, {required clearPendingFirst, currentWeek}) async =>
            scheduledDays.add(settings.days),
      );

      final first = coordinator.schedule(
        NotificationSettings(days: {DayOfWeek.mon}),
      );
      final latest = coordinator.schedule(
        NotificationSettings(days: {DayOfWeek.fri}),
      );

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
        schedule: (settings, {required clearPendingFirst, currentWeek}) async {
          events.add('schedule');
          scheduleStarted.complete();
          await releaseSchedule.future;
        },
        cancel: () async => events.add('cancel'),
      );

      final scheduled = coordinator.schedule(
        NotificationSettings(days: {DayOfWeek.mon}),
      );
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
        schedule: (settings, {required clearPendingFirst, currentWeek}) async =>
            scheduleCount++,
      );

      final scheduled = coordinator.schedule(NotificationSettings());
      coordinator.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(scheduleCount, isZero);
      expect(await scheduled, NotificationScheduleOutcome.disposed);
    });

    test('예약 콜백 실패를 반환 Future에 전달한다', () async {
      final coordinator = NotificationScheduleCoordinator(
        debounce: Duration.zero,
        schedule: (settings, {required clearPendingFirst, currentWeek}) async =>
            throw StateError('schedule failed'),
      );

      await expectLater(
        coordinator.schedule(NotificationSettings()),
        throwsStateError,
      );
    });

    test('즉시 예약은 디바운스를 기다리지 않는다', () async {
      var scheduleCount = 0;
      final coordinator = NotificationScheduleCoordinator(
        debounce: const Duration(days: 1),
        schedule: (settings, {required clearPendingFirst, currentWeek}) async =>
            scheduleCount++,
      );

      final outcome = await coordinator.scheduleNow(NotificationSettings());

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
