import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'allergy/allergy_settings.dart';
import 'notification/notification_settings.dart';
import 'notification/notification_settings_store.dart';

class AppSettings extends ChangeNotifier {
  final SharedPreferences _prefs;

  AllergySettings _allergy;
  NotificationSettings _notification;
  ThemeMode _themeMode;
  final NotificationScheduleCoordinator _notificationScheduleCoordinator;

  AllergySettings get allergy => _allergy;
  NotificationSettings get notification => _notification;
  ThemeMode get themeMode => _themeMode;

  AppSettings(
    this._prefs, {
    NotificationScheduleCoordinator? notificationScheduleCoordinator,
  }) : _notificationScheduleCoordinator =
           notificationScheduleCoordinator ?? NotificationScheduleCoordinator(),
       _allergy = _loadAllergy(_prefs),
       _notification = loadNotificationSettings(_prefs),
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
      _requestNotificationReschedule(immediately: true);
    } else {
      unawaited(_notificationScheduleCoordinator.cancelAll());
    }
  }

  /// 앱 시작 등에서 현재 알림 설정을 다시 Workmanager에 반영한다.
  void rescheduleKeywordNotifications() {
    if (_notification.enabled) {
      _requestNotificationReschedule(immediately: true);
    }
  }

  void addNotificationKeyword(String kw) {
    final trimmed = kw.trim();
    if (trimmed.isEmpty) return;
    if (_notification.keywords.contains(trimmed)) return;
    final next = [..._notification.keywords, trimmed];
    _notification = _notification.copyWith(keywords: next);
    _prefs.setStringList(StorageKeys.notificationKeywords, next);
    notifyListeners();
  }

  void removeNotificationKeyword(String kw) {
    if (!_notification.keywords.contains(kw)) return;
    final next = _notification.keywords.where((k) => k != kw).toList();
    _notification = _notification.copyWith(keywords: next);
    _prefs.setStringList(StorageKeys.notificationKeywords, next);
    notifyListeners();
  }

  /// [time]이 null이면 해당 시간대 알림을 끈다(마지막 선택 시각은 기억해 둔다).
  /// 그렇지 않으면 해당 시간대에 지정 시각으로 알림을 등록한다.
  void setPeriodAlertTime(MealNotificationPeriod period, TimeOfDay? time) {
    final next = Map<MealNotificationPeriod, TimeOfDay?>.from(
      _notification.alertTimes,
    );
    final remembered = Map<MealNotificationPeriod, TimeOfDay>.from(
      _notification.rememberedTimes,
    );
    if (time == null) {
      next.remove(period);
    } else {
      next[period] = time;
      remembered[period] = time;
    }
    _notification = _notification.copyWith(
      alertTimes: next,
      rememberedTimes: remembered,
    );

    final key = '${StorageKeys.notificationPeriodTimePrefix}${period.name}';
    if (time == null) {
      _prefs.remove(key);
    } else {
      _prefs.setString(key, _formatTime(time));
      _prefs.setString(
        '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
        _formatTime(time),
      );
    }
    notifyListeners();

    if (_notification.enabled) {
      _requestNotificationReschedule();
    }
  }

  /// 학생·교직원 식당 알림 대상을 설정한다. 기숙사 식당은 여기서 다루지 않고
  /// [setNotificationDormMealTypes]가 전담한다 (진실 공급원을 하나로 유지).
  void setNotificationCafeterias(Set<Cafeteria> cafeterias) {
    final filtered = cafeterias.where((c) => c != Cafeteria.dormitory).toSet();
    _notification = _notification.copyWith(cafeterias: filtered);
    _prefs.setStringList(
      StorageKeys.notificationCafeterias,
      filtered.map((e) => e.name).toList(),
    );
    notifyListeners();
  }

  /// 기숙사 식당 알림 대상 메뉴 종류(한식/할랄)를 설정한다.
  /// 이 값이 비어있으면 기숙사 식당 자체가 알림 대상에서 빠진 것으로 취급된다.
  void setNotificationDormMealTypes(Set<DormMealType> types) {
    _notification = _notification.copyWith(dormMealTypes: types);
    _prefs.setStringList(
      StorageKeys.notificationDormMealTypes,
      types.map((e) => e.name).toList(),
    );
    notifyListeners();
  }

  /// 알림을 받을 요일 집합을 설정하고, 다음 활성 메뉴 요일로 다시 예약한다.
  void setNotificationDays(Set<DayOfWeek> days) {
    _notification = _notification.copyWith(days: days);
    _prefs.setStringList(
      StorageKeys.notificationDays,
      days.map((e) => e.name).toList(),
    );
    notifyListeners();
    if (_notification.enabled) {
      _requestNotificationReschedule();
    }
  }

  void _requestNotificationReschedule({bool immediately = false}) {
    unawaited(
      immediately
          ? _notificationScheduleCoordinator.scheduleNow(
              _notification.alertTimes,
              _notification.days,
            )
          : _notificationScheduleCoordinator.schedule(
              _notification.alertTimes,
              _notification.days,
            ),
    );
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
    _themeMode = ThemeMode.system;
    unawaited(_notificationScheduleCoordinator.cancelAll());
    _prefs.setStringList(StorageKeys.allergenIds, []);
    _prefs.setBool(StorageKeys.notificationEnabled, false);
    _prefs.setStringList(StorageKeys.notificationKeywords, []);
    for (final period in MealNotificationPeriod.values) {
      _prefs.remove(
        '${StorageKeys.notificationPeriodTimePrefix}${period.name}',
      );
      _prefs.remove(
        '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
      );
    }
    _prefs.remove(StorageKeys.notificationCafeterias); // 기본값(빈 집합)으로 복귀
    _prefs.remove(StorageKeys.notificationDormMealTypes); // 기본값(한식+할랄)으로 복귀
    _prefs.remove(StorageKeys.notificationDays); // 기본값(모든 요일)으로 복귀
    _prefs.setString(StorageKeys.themeMode, ThemeMode.system.name);
    notifyListeners();
  }

  @override
  void dispose() {
    _notificationScheduleCoordinator.dispose();
    super.dispose();
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

  static ThemeMode _loadThemeMode(SharedPreferences p) =>
      ThemeMode.values.asNameMap()[p.getString(StorageKeys.themeMode)] ??
      ThemeMode.system;

  // --- 시간 문자열 파싱/포매팅 헬퍼 ---

  static String _formatTime(TimeOfDay t) => '${t.hour}:${t.minute}';
}
