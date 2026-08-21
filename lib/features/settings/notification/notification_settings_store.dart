import 'package:flutter/material.dart' show TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/enum_utils.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'notification_settings.dart';

// 구버전(단일 키워드) SharedPreferences 키. 마이그레이션 용도로만 참조.
const _legacyKeywordKey = 'settings_notification_keyword';

// 구버전(단일 알림 시각) SharedPreferences 키. 마이그레이션 용도로만 참조.
const _legacyAlertTimeKey = 'settings_notification_time';

/// 저장된 알림 설정을 읽고 구버전 값을 현재 형식으로 마이그레이션한다.
NotificationSettings loadNotificationSettings(SharedPreferences prefs) {
  // 기숙사 식당 선택 여부는 dormMealTypes 하나로만 판단한다. 이 키가 도입되기
  // 전 저장값은 cafeterias의 기숙사 선택 여부를 한식/할랄 기본값으로 옮긴다.
  final cafeteriaNames = prefs.getStringList(
    StorageKeys.notificationCafeterias,
  );
  final storedCafeterias = cafeteriaNames == null
      ? const <Cafeteria>{}
      : enumSetFromNames(cafeteriaNames, Cafeteria.values);
  final hadDormitoryBefore =
      cafeteriaNames == null || storedCafeterias.contains(Cafeteria.dormitory);
  final cafeterias = storedCafeterias
      .where((cafeteria) => cafeteria != Cafeteria.dormitory)
      .toSet();

  final dormMealTypeNames = prefs.getStringList(
    StorageKeys.notificationDormMealTypes,
  );
  final dormMealTypes = dormMealTypeNames != null
      ? enumSetFromNames(dormMealTypeNames, DormMealType.values)
      : (hadDormitoryBefore
            ? const <DormMealType>{DormMealType.korean, DormMealType.halal}
            : const <DormMealType>{});

  var keywords = prefs.getStringList(StorageKeys.notificationKeywords);
  if (keywords == null) {
    final legacy = prefs.getString(_legacyKeywordKey)?.trim();
    keywords = legacy != null && legacy.isNotEmpty ? [legacy] : <String>[];
    if (keywords.isNotEmpty) {
      prefs.setStringList(StorageKeys.notificationKeywords, keywords);
      prefs.remove(_legacyKeywordKey);
    }
  }

  // 저장된 문자열이 해당 시간대의 유효 슬롯이 아니면 꺼진 상태로 취급한다.
  final alertTimes = <MealNotificationPeriod, TimeOfDay?>{};
  for (final period in MealNotificationPeriod.values) {
    final stored = prefs.getString(
      '${StorageKeys.notificationPeriodTimePrefix}${period.name}',
    );
    if (stored == null) continue;
    final parsed = _parseTime(stored);
    if (parsed != null && _isWithinPeriodSlots(period, parsed)) {
      alertTimes[period] = parsed;
    }
  }

  if (alertTimes.isEmpty) {
    final legacyTimeString = prefs.getString(_legacyAlertTimeKey);
    if (legacyTimeString != null) {
      final legacyTime = _parseTime(legacyTimeString);
      if (legacyTime != null) {
        final matched = _snapLegacyTime(legacyTime);
        if (matched != null) {
          alertTimes[matched.$1] = matched.$2;
          prefs.setString(
            '${StorageKeys.notificationPeriodTimePrefix}${matched.$1.name}',
            _formatTime(matched.$2),
          );
        }
      }
      prefs.remove(_legacyAlertTimeKey);
    }
  }

  final rememberedTimes = <MealNotificationPeriod, TimeOfDay>{};
  for (final period in MealNotificationPeriod.values) {
    final stored = prefs.getString(
      '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
    );
    final parsed = stored != null ? _parseTime(stored) : null;
    if (parsed != null && _isWithinPeriodSlots(period, parsed)) {
      rememberedTimes[period] = parsed;
    } else if (alertTimes[period] != null) {
      rememberedTimes[period] = alertTimes[period]!;
    }
  }

  return NotificationSettings(
    enabled: prefs.getBool(StorageKeys.notificationEnabled) ?? false,
    keywords: keywords,
    alertTimes: alertTimes,
    rememberedTimes: rememberedTimes,
    cafeterias: cafeterias,
    dormMealTypes: dormMealTypes,
    days: notificationDaysFromNames(
      prefs.getStringList(StorageKeys.notificationDays),
    ),
  );
}

String _formatTime(TimeOfDay time) => '${time.hour}:${time.minute}';

TimeOfDay? _parseTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

bool _isWithinPeriodSlots(MealNotificationPeriod period, TimeOfDay time) =>
    period.allSlots.any(
      (slot) => slot.hour == time.hour && slot.minute == time.minute,
    );

(MealNotificationPeriod, TimeOfDay)? _snapLegacyTime(TimeOfDay time) {
  for (final period in MealNotificationPeriod.values) {
    if (_isWithinPeriodSlots(period, time)) return (period, time);
  }
  return null;
}
