import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';

void main() {
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
