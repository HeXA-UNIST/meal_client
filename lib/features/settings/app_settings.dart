import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'allergy_settings.dart';
import 'notification_settings.dart';
import 'widget_settings.dart';

class AppSettings extends ChangeNotifier {
  final SharedPreferences _prefs;

  AllergySettings _allergy;
  NotificationSettings _notification;
  WidgetSettings _widget;
  ThemeMode _themeMode;

  AllergySettings get allergy => _allergy;
  NotificationSettings get notification => _notification;
  WidgetSettings get widget => _widget;
  ThemeMode get themeMode => _themeMode;

  AppSettings(this._prefs)
      : _allergy = _loadAllergy(_prefs),
        _notification = _loadNotification(_prefs),
        _widget = _loadWidget(_prefs),
        _themeMode = _loadThemeMode(_prefs);

  // --- 알레르기 ---

  void toggleAllergen(int id) {
    _allergy = _allergy.toggle(id);
    _prefs.setStringList(
      StorageKeys.allergenIds,
      _allergy.enabledIds.map((e) => '$e').toList(),
    );
    notifyListeners();
  }

  // --- 알림 ---

  void setNotificationEnabled(bool v) {
    _notification = _notification.copyWith(enabled: v);
    _prefs.setBool(StorageKeys.notificationEnabled, v);
    notifyListeners();
    if (v) {
      unawaited(scheduleKeywordNotification(_notification.alertTime));
    } else {
      unawaited(cancelKeywordNotification());
    }
  }

  void setNotificationKeyword(String kw) {
    final trimmed = kw.trim();
    _notification = _notification.copyWith(keyword: trimmed);
    if (trimmed.isNotEmpty) {
      _prefs.setString(StorageKeys.notificationKeyword, trimmed);
    } else {
      _prefs.remove(StorageKeys.notificationKeyword);
    }
    notifyListeners();
  }

  void setNotificationTime(TimeOfDay time) {
    _notification = _notification.copyWith(alertTime: time);
    _prefs.setString(
        StorageKeys.notificationTime, '${time.hour}:${time.minute}');
    notifyListeners();
    if (_notification.enabled) {
      unawaited(scheduleKeywordNotification(time));
    }
  } 

  void setNotificationCafeterias(Set<Cafeteria> cafeterias) {
    _notification = _notification.copyWith(cafeterias: cafeterias);
    _prefs.setStringList(
      StorageKeys.notificationCafeterias,
      cafeterias.map((e) => e.name).toList(),
    );
    notifyListeners();
  }

  // --- 위젯 ---

  void setWidgetCafeteria(Cafeteria c) {
    _widget = _widget.copyWith(cafeteria: c);
    _prefs.setString(StorageKeys.widgetCafeteria, c.name);
    notifyListeners();
  }

  void setWidgetMealOfDay(MealOfDay m) {
    _widget = _widget.copyWith(mealOfDay: m);
    _prefs.setString(StorageKeys.widgetMealOfDay, m.name);
    notifyListeners();
  }

  // --- 테마 ---

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _prefs.setString(StorageKeys.themeMode, mode.name);
    notifyListeners();
  }

  // --- 전체 초기화 ---

  void resetAll() {
    _allergy = _allergy.reset();
    _notification = _notification.reset();
    _widget = _widget.reset();
    _themeMode = ThemeMode.system;
    unawaited(cancelKeywordNotification());
    _prefs.setStringList(StorageKeys.allergenIds, []);
    _prefs.setBool(StorageKeys.notificationEnabled, false);
    _prefs.remove(StorageKeys.notificationKeyword);
    _prefs.setString(StorageKeys.notificationTime, '8:0');
    _prefs.setStringList(
        StorageKeys.notificationCafeterias, [Cafeteria.dormitory.name]);
    _prefs.setString(StorageKeys.widgetCafeteria, Cafeteria.dormitory.name);
    _prefs.setString(StorageKeys.widgetMealOfDay, MealOfDay.lunch.name);
    _prefs.setString(StorageKeys.themeMode, ThemeMode.system.name);
    notifyListeners();
  }

  // --- 로드 헬퍼 ---

  static AllergySettings _loadAllergy(SharedPreferences p) {
    final ids = (p.getStringList(StorageKeys.allergenIds) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => id >= 1 && id <= 19)
        .toSet();
    return AllergySettings(enabledIds: ids);
  }

  static NotificationSettings _loadNotification(SharedPreferences p) {
    final timeParts =
        (p.getString(StorageKeys.notificationTime) ?? '8:0').split(':');
    final hour =
        int.tryParse(timeParts.isNotEmpty ? timeParts[0] : '') ?? 8;
    final minute =
        int.tryParse(timeParts.length > 1 ? timeParts[1] : '') ?? 0;
    final cafeteriaMap = Cafeteria.values.asNameMap();
    final cafeteriaNames = p.getStringList(StorageKeys.notificationCafeterias);
    final cafeterias = cafeteriaNames == null
        ? <Cafeteria>{Cafeteria.dormitory}
        : {
            for (final n in cafeteriaNames)
              if (cafeteriaMap[n] != null) cafeteriaMap[n]!,
          };
    return NotificationSettings(
      enabled: p.getBool(StorageKeys.notificationEnabled) ?? false,
      keyword: p.getString(StorageKeys.notificationKeyword) ?? '',
      alertTime: TimeOfDay(hour: hour, minute: minute),
      cafeterias: cafeterias.isEmpty ? {Cafeteria.dormitory} : cafeterias,
    );
  }

  static WidgetSettings _loadWidget(SharedPreferences p) {
    final cafeteriaMap = Cafeteria.values.asNameMap();
    final mealOfDayMap = MealOfDay.values.asNameMap();
    return WidgetSettings(
      cafeteria: cafeteriaMap[p.getString(StorageKeys.widgetCafeteria)] ??
          Cafeteria.dormitory,
      mealOfDay: mealOfDayMap[p.getString(StorageKeys.widgetMealOfDay)] ??
          MealOfDay.lunch,
    );
  }

  static ThemeMode _loadThemeMode(SharedPreferences p) =>
      ThemeMode.values.asNameMap()[p.getString(StorageKeys.themeMode)] ??
      ThemeMode.system;
}
