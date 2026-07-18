import 'package:flutter/material.dart' show TimeOfDay;

import 'package:meal_client/core/enum_utils.dart';
import 'package:meal_client/domain/meal.dart';

enum MealAlertPeriod {
  morning(
    startHour: 7,
    startMinute: 30,
    endHour: 8,
    endMinute: 30,
    mealOfDay: MealOfDay.breakfast,
    tomorrow: false,
  ),
  lunch(
    startHour: 10,
    startMinute: 30,
    endHour: 11,
    endMinute: 30,
    mealOfDay: MealOfDay.lunch,
    tomorrow: false,
  ),
  dinner(
    startHour: 16,
    startMinute: 30,
    endHour: 17,
    endMinute: 30,
    mealOfDay: MealOfDay.dinner,
    tomorrow: false,
  ),
  night(
    startHour: 21,
    startMinute: 0,
    endHour: 22,
    endMinute: 0,
    mealOfDay: MealOfDay.breakfast,
    tomorrow: true,
  );

  const MealAlertPeriod({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.mealOfDay,
    required this.tomorrow,
  });

  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  /// 이 시간대가 검사할 식사 시간대
  final MealOfDay mealOfDay;

  /// 오늘(false) 내일(true)
  final bool tomorrow;

  TimeOfDay get startTime => TimeOfDay(hour: startHour, minute: startMinute);
  TimeOfDay get endTime => TimeOfDay(hour: endHour, minute: endMinute);

  /// 슬롯 기본값: 각 범위의 중간 지점 (아침 8:00, 점심 11:00, 저녁 17:00, 밤 21:30)
  TimeOfDay get defaultSlot {
    final slots = allSlots;
    return slots[slots.length ~/ 2];
  }

  /// 15분 단위 슬롯 목록. 시작·끝 포함.
  List<TimeOfDay> get allSlots {
    final result = <TimeOfDay>[];
    var h = startHour;
    var m = startMinute;
    while (h < endHour || (h == endHour && m <= endMinute)) {
      result.add(TimeOfDay(hour: h, minute: m));
      m += 15;
      if (m >= 60) {
        h += m ~/ 60;
        m %= 60;
      }
    }
    return result;
  }

  static MealAlertPeriod? tryFromName(String name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// [period]가 검사할 메뉴의 요일을 반환한다.
///
/// [kstNow]는 한국 표준시 기준이어야 한다. 밤 알림은 다음 날 아침 메뉴를
/// 검사하므로, 요일 선택도 실행 시점이 아닌 메뉴 대상 날짜를 기준으로 한다.
DayOfWeek notificationTargetDayFor(MealAlertPeriod period, DateTime kstNow) {
  final targetDate = period.tomorrow
      ? kstNow.add(const Duration(days: 1))
      : kstNow;
  return DayOfWeek.values[targetDate.weekday - 1];
}

/// 저장된 요일 이름을 알림 요일 집합으로 변환한다.
///
/// 저장값이 없으면 기존 사용자와의 호환을 위해 모든 요일을 활성화한다.
Set<DayOfWeek> notificationDaysFromNames(Iterable<String>? names) {
  if (names == null) return DayOfWeek.values.toSet();

  return enumSetFromNames(names, DayOfWeek.values);
}
