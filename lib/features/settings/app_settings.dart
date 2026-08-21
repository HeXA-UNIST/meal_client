import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/ios_meal_notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'allergy/allergy_settings.dart';
import 'notification/notification_settings.dart';
import 'notification/notification_settings_store.dart';

typedef NotificationAuthorizationStatusReader =
    Future<MealNotificationAuthorizationStatus> Function();

class AppSettings extends ChangeNotifier {
  final SharedPreferences _prefs;

  AllergySettings _allergy;
  NotificationSettings _notification;
  ThemeMode _themeMode;
  final NotificationScheduleCoordinator _notificationScheduleCoordinator;
  final Future<bool> Function() _requestNotificationPermission;
  final NotificationAuthorizationStatusReader _readAuthorizationStatus;
  MealNotificationAuthorizationStatus? _notificationAuthorizationStatus;

  AllergySettings get allergy => _allergy;
  NotificationSettings get notification => _notification;
  ThemeMode get themeMode => _themeMode;
  MealNotificationAuthorizationStatus? get notificationAuthorizationStatus =>
      _notificationAuthorizationStatus;

  AppSettings(
    this._prefs, {
    NotificationScheduleCoordinator? notificationScheduleCoordinator,
    Future<bool> Function()? notificationPermissionRequester,
    NotificationAuthorizationStatusReader?
    notificationAuthorizationStatusReader,
  }) : _notificationScheduleCoordinator =
           notificationScheduleCoordinator ?? NotificationScheduleCoordinator(),
       _requestNotificationPermission =
           notificationPermissionRequester ?? requestNotificationPermission,
       _readAuthorizationStatus =
           notificationAuthorizationStatusReader ??
           mealNotificationAuthorizationStatus,
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

  Future<bool> setNotificationEnabled(bool v) async {
    if (v) {
      final granted = await _requestNotificationPermission();
      _notificationAuthorizationStatus = granted
          ? MealNotificationAuthorizationStatus.enabled
          : MealNotificationAuthorizationStatus.notAuthorized;
      if (!granted) {
        notifyListeners();
        return false;
      }
    } else {
      _notificationAuthorizationStatus = null;
    }
    _notification = _notification.copyWith(enabled: v);
    _prefs.setBool(StorageKeys.notificationEnabled, v);
    notifyListeners();
    if (v) {
      _requestNotificationReschedule(immediately: true);
    } else {
      _cancelAllMealNotifications();
    }
    return true;
  }

  /// 앱 시작 시 현재 알림 설정을 플랫폼 예약 방식에 반영한다.
  void rescheduleMealNotifications() {
    if (_notification.enabled) {
      unawaited(refreshNotificationAuthorizationStatus());
      _requestNotificationReschedule(immediately: true);
    }
  }

  /// 최초 foreground 식단 갱신 결과로 iOS 사전 예약 내용을 즉시 갱신한다.
  void reconcileIosMealNotificationsAfterInitialRefresh(
    WeekMeal currentWeekMeal, {
    DateTime? now,
  }) {
    if (mealNotificationPlatform != MealNotificationPlatform.ios ||
        !_notification.enabled) {
      return;
    }
    final instant = now ?? DateTime.now();
    _requestNotificationReschedule(
      immediately: true,
      currentWeek: (
        startDate: kstWeekStartForInstant(instant),
        weekMeal: currentWeekMeal,
      ),
    );
  }

  /// 앱 시작 시 외부 설정에서 바뀐 iOS 권한 상태를 설정 화면에 반영한다.
  Future<void> refreshNotificationAuthorizationStatus() async {
    final status = await _readAuthorizationStatus();
    if (!_notification.enabled ||
        status == MealNotificationAuthorizationStatus.notApplicable ||
        status == _notificationAuthorizationStatus) {
      return;
    }
    _notificationAuthorizationStatus = status;
    notifyListeners();
  }

  void addNotificationKeyword(String kw) {
    final trimmed = kw.trim();
    if (trimmed.isEmpty) return;
    if (_notification.keywords.contains(trimmed)) return;
    final next = [..._notification.keywords, trimmed];
    _notification = _notification.copyWith(keywords: next);
    _prefs.setStringList(StorageKeys.notificationKeywords, next);
    notifyListeners();
    if (_notification.enabled) {
      _requestNotificationReschedule(clearPendingFirst: true);
    }
  }

  void removeNotificationKeyword(String kw) {
    if (!_notification.keywords.contains(kw)) return;
    final next = _notification.keywords.where((k) => k != kw).toList();
    _notification = _notification.copyWith(keywords: next);
    _prefs.setStringList(StorageKeys.notificationKeywords, next);
    notifyListeners();
    if (_notification.enabled) {
      _requestNotificationReschedule(clearPendingFirst: true);
    }
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
      _requestNotificationReschedule(clearPendingFirst: true);
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
    if (_notification.enabled) {
      _requestNotificationReschedule(clearPendingFirst: true);
    }
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
    if (_notification.enabled) {
      _requestNotificationReschedule(clearPendingFirst: true);
    }
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
      _requestNotificationReschedule(clearPendingFirst: true);
    }
  }

  void _requestNotificationReschedule({
    bool immediately = false,
    bool clearPendingFirst = false,
    IosMealWeek? currentWeek,
  }) {
    unawaited(
      (immediately
              ? _notificationScheduleCoordinator.scheduleNow(
                  _notification,
                  clearPendingFirst: clearPendingFirst,
                  currentWeek: currentWeek,
                )
              : _notificationScheduleCoordinator.schedule(
                  _notification,
                  clearPendingFirst: clearPendingFirst,
                  currentWeek: currentWeek,
                ))
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint(
              '[BapU] meal notification reconciliation failed: $error',
            );
            debugPrintStack(stackTrace: stackTrace);
            return NotificationScheduleOutcome.canceled;
          }),
    );
  }

  void _cancelAllMealNotifications() {
    unawaited(
      _notificationScheduleCoordinator.cancelAll().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint('[BapU] meal notification cancellation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }),
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
    _notificationAuthorizationStatus = null;
    _themeMode = ThemeMode.system;
    _cancelAllMealNotifications();
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
