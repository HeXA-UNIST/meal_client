import 'dart:async';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';

void main() {
  test('활성 메뉴 요일과 night 경계를 기준으로 다음 실행 시각을 계산한다', () {
    final cases =
        <
          ({
            MealNotificationPeriod period,
            Set<DayOfWeek> days,
            DateTime now,
            DateTime? expected,
          })
        >[
          (
            period: MealNotificationPeriod.night,
            days: {DayOfWeek.mon},
            now: DateTime(2026, 7, 19, 20),
            expected: DateTime(2026, 7, 19, 21, 30),
          ),
          (
            period: MealNotificationPeriod.lunch,
            days: {DayOfWeek.mon},
            now: DateTime(2026, 7, 16, 10),
            expected: DateTime(2026, 7, 20, 11),
          ),
          (
            period: MealNotificationPeriod.lunch,
            days: const {},
            now: DateTime(2026, 7, 16, 10),
            expected: null,
          ),
        ];

    for (final scenario in cases) {
      expect(
        nextEnabledFireTime(
          period: scenario.period,
          alertTime: scenario.period == MealNotificationPeriod.night
              ? const TimeOfDay(hour: 21, minute: 30)
              : const TimeOfDay(hour: 11, minute: 0),
          enabledDays: scenario.days,
          now: scenario.now,
        ),
        scenario.expected,
      );
    }

    final sundayNight = DateTime.utc(2026, 7, 19, 12, 30);
    expect(
      notificationTargetDateFor(MealNotificationPeriod.night, sundayNight),
      DateTime.utc(2026, 7, 20),
    );
    expect(
      kstCalendarDate(DateTime.parse('2026-07-19T17:30:00-07:00')),
      DateTime.utc(2026, 7, 20),
    );
  });

  test('Android night task는 월요일 대상 날짜를 저장하고 실행 뒤 다음 task를 예약한다', () async {
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

    DateTime? checkedDate;
    var reschedules = 0;
    await handleKeywordNotificationTask(
      period: MealNotificationPeriod.night,
      targetDateInput: capturedInputData?['targetDate'] as String?,
      runCheck: (_, targetDate) async => checkedDate = targetDate,
      reschedule: (_) async => reschedules++,
    );

    expect(capturedInputData, {'targetDate': '2026-07-20'});
    expect(checkedDate, DateTime.utc(2026, 7, 20));
    expect(reschedules, 1);
  });

  test('이전 세대가 끝나기 전에 최신 예약만 플랫폼 변경을 적용한다', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final appliedDays = <Set<DayOfWeek>>[];
    final coordinator = NotificationScheduleCoordinator(
      debounce: Duration.zero,
      schedule: (settings, {required isCurrent}) async {
        if (settings.days.contains(DayOfWeek.mon)) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        if (isCurrent()) appliedDays.add(settings.days);
      },
    );
    addTearDown(coordinator.dispose);

    final old = coordinator.scheduleNow(
      NotificationSettings(days: {DayOfWeek.mon}),
    );
    await firstStarted.future;
    final latest = coordinator.scheduleNow(
      NotificationSettings(days: {DayOfWeek.fri}),
    );
    releaseFirst.complete();

    expect(await old, NotificationScheduleOutcome.superseded);
    expect(await latest, NotificationScheduleOutcome.scheduled);
    expect(appliedDays, [
      {DayOfWeek.fri},
    ]);
  });
}
