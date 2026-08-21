import 'package:flutter/material.dart' show TimeOfDay;

import 'meal_notification_period.dart';

typedef LocalDateTimeFactory =
    DateTime Function(int year, int month, int day, int hour, int minute);

/// KST 메뉴 대상 날짜를 기기 현지 알림 시각으로 역변환한다.
DateTime fireInstantForTarget({
  required MealNotificationPeriod period,
  required DateTime targetKstDate,
  required TimeOfDay alertTime,
  LocalDateTimeFactory? localDateTimeFactory,
}) {
  final createLocal =
      localDateTimeFactory ??
      (year, month, day, hour, minute) =>
          DateTime(year, month, day, hour, minute);
  final baseDate = targetKstDate.subtract(
    Duration(days: period.tomorrow ? 1 : 0),
  );
  for (final dayOffset in const [0, -1, 1]) {
    final localDate = baseDate.add(Duration(days: dayOffset));
    final candidate = createLocal(
      localDate.year,
      localDate.month,
      localDate.day,
      alertTime.hour,
      alertTime.minute,
    );
    final roundTrip = notificationTargetDateFor(period, candidate);
    if (_sameCalendarDate(roundTrip, targetKstDate)) return candidate;
  }
  throw StateError('메뉴 대상 날짜에 대응하는 현지 알림 시각을 찾지 못했습니다.');
}

bool _sameCalendarDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
