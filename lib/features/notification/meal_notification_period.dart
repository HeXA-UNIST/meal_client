import 'package:flutter/material.dart' show TimeOfDay;

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/enum_utils.dart';
import 'package:meal_client/domain/meal.dart';

enum MealNotificationPeriod {
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

  const MealNotificationPeriod({
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
}

/// 실제 시각을 날짜만 가진 KST 달력값으로 정규화한다.
///
/// 반환값은 UTC 표기를 빌린 날짜값일 뿐 실제 시각이 아니다. 다시 [toKst]에
/// 전달하면 KST 보정이 중복되므로 날짜 비교와 주 시작일 계산에만 사용한다.
DateTime kstCalendarDate(DateTime instant) {
  final kst = MealTimeConfig.toKst(instant);
  return DateTime.utc(kst.year, kst.month, kst.day);
}

/// [period]가 검사할 메뉴의 KST 날짜를 반환한다.
DateTime notificationTargetDateFor(
  MealNotificationPeriod period,
  DateTime instant,
) {
  final date = kstCalendarDate(instant);
  return period.tomorrow ? date.add(const Duration(days: 1)) : date;
}

/// 저장된 요일 이름을 알림 요일 집합으로 변환한다.
///
/// 저장값이 없으면 기존 사용자와의 호환을 위해 모든 요일을 활성화한다.
Set<DayOfWeek> notificationDaysFromNames(Iterable<String>? names) {
  if (names == null) return DayOfWeek.values.toSet();

  return enumSetFromNames(names, DayOfWeek.values);
}
