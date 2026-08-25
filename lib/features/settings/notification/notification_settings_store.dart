import 'package:flutter/material.dart' show TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/enum_utils.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'notification_settings.dart';

/// 현재 형식으로 저장된 알림 설정을 읽는다.
NotificationSettings loadNotificationSettings(SharedPreferences prefs) {
  final cafeteriaNames = prefs.getStringList(
    StorageKeys.notificationCafeterias,
  );
  final storedCafeterias = cafeteriaNames == null
      ? const <Cafeteria>{}
      : enumSetFromNames(cafeteriaNames, Cafeteria.values);
  final cafeterias = storedCafeterias
      .where((cafeteria) => cafeteria != Cafeteria.dormitory)
      .toSet();

  final dormMealTypeNames = prefs.getStringList(
    StorageKeys.notificationDormMealTypes,
  );
  final dormMealTypes = dormMealTypeNames != null
      ? enumSetFromNames(dormMealTypeNames, DormMenuType.values)
      : const <DormMenuType>{DormMenuType.korean, DormMenuType.halal};

  final keywords = prefs.getStringList(StorageKeys.notificationKeywords) ?? [];

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
