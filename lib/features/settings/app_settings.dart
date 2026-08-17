import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/enum_utils.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_alert_period.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'allergy_settings.dart';
import 'notification_settings.dart';

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
       _notification = _loadNotification(_prefs),
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
  void setPeriodAlertTime(MealAlertPeriod period, TimeOfDay? time) {
    final next = Map<MealAlertPeriod, TimeOfDay?>.from(
      _notification.alertTimes,
    );
    final remembered = Map<MealAlertPeriod, TimeOfDay>.from(
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
    for (final period in MealAlertPeriod.values) {
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

  // 구버전(단일 키워드) SharedPreferences 키. 마이그레이션 용도로만 참조.
  static const _legacyKeywordKey = 'settings_notification_keyword';

  // 구버전(단일 알림 시각) SharedPreferences 키. 마이그레이션 용도로만 참조.
  static const _legacyAlertTimeKey = 'settings_notification_time';

  static NotificationSettings _loadNotification(SharedPreferences p) {
    // 기숙사 식당의 알림 대상 여부는 dormMealTypes 하나로만 판단하므로
    // cafeterias에서는 항상 걸러낸다. dormMealTypes 키가 아직 없는(=이 기능 이전)
    // 저장값이라면, 구버전에서 기숙사가 선택돼 있었는지로 기본값(둘 다 켜짐/모두 꺼짐)을
    // 정해 기존 사용자의 알림 동작이 바뀌지 않게 한다.
    final cafeteriaNames = p.getStringList(StorageKeys.notificationCafeterias);
    final storedCafeterias = cafeteriaNames == null
        ? const <Cafeteria>{}
        : enumSetFromNames(cafeteriaNames, Cafeteria.values);
    final hadDormitoryBefore =
        cafeteriaNames == null || storedCafeterias.contains(Cafeteria.dormitory);
    final cafeterias = storedCafeterias
        .where((c) => c != Cafeteria.dormitory)
        .toSet();

    final dormMealTypeNames = p.getStringList(
      StorageKeys.notificationDormMealTypes,
    );
    final dormMealTypes = dormMealTypeNames != null
        ? enumSetFromNames(dormMealTypeNames, DormMealType.values)
        : (hadDormitoryBefore
              ? const <DormMealType>{DormMealType.korean, DormMealType.halal}
              : const <DormMealType>{});

    // 키워드 로드 + 구버전 마이그레이션
    var keywords = p.getStringList(StorageKeys.notificationKeywords);
    if (keywords == null) {
      final legacy = p.getString(_legacyKeywordKey)?.trim();
      keywords = (legacy != null && legacy.isNotEmpty) ? [legacy] : <String>[];
      if (keywords.isNotEmpty) {
        p.setStringList(StorageKeys.notificationKeywords, keywords);
        p.remove(_legacyKeywordKey);
      }
    }

    // 시간대별 알림 시각 로드.
    // 저장된 문자열이 해당 시간대의 유효 슬롯 중 하나가 아니면 무시(=꺼진 상태).
    final alertTimes = <MealAlertPeriod, TimeOfDay?>{};
    for (final period in MealAlertPeriod.values) {
      final key = '${StorageKeys.notificationPeriodTimePrefix}${period.name}';
      final stored = p.getString(key);
      if (stored == null) continue;
      final parsed = _parseTime(stored);
      if (parsed != null && _isWithinPeriodSlots(period, parsed)) {
        alertTimes[period] = parsed;
      }
    }

    // 구버전(단일 알림 시각) 마이그레이션: 저장된 시각이 어느 시간대 범위 안에
    // 들어가면 그 시간대에 배치하고, 아니면 아침 기본 슬롯으로 보내고 구 키는 삭제.
    if (alertTimes.isEmpty) {
      final legacyTimeStr = p.getString(_legacyAlertTimeKey);
      if (legacyTimeStr != null) {
        final legacyTime = _parseTime(legacyTimeStr);
        if (legacyTime != null) {
          final matched = _snapLegacyTime(legacyTime);
          if (matched != null) {
            alertTimes[matched.$1] = matched.$2;
            p.setString(
              '${StorageKeys.notificationPeriodTimePrefix}${matched.$1.name}',
              _formatTime(matched.$2),
            );
          }
        }
        p.remove(_legacyAlertTimeKey);
      }
    }

    // 시간대별 "마지막 선택 시각" 로드. 꺼진 시간대라도 이전 선택을 복원하기 위함.
    // 저장된 값이 없으면 현재 켜져 있는 시각으로 시드한다.
    final remembered = <MealAlertPeriod, TimeOfDay>{};
    for (final period in MealAlertPeriod.values) {
      final key =
          '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}';
      final stored = p.getString(key);
      final parsed = stored != null ? _parseTime(stored) : null;
      if (parsed != null && _isWithinPeriodSlots(period, parsed)) {
        remembered[period] = parsed;
      } else if (alertTimes[period] != null) {
        remembered[period] = alertTimes[period]!;
      }
    }

    // 알림 요일 로드. 키가 없으면 모든 요일 활성(기본값).
    final days = notificationDaysFromNames(
      p.getStringList(StorageKeys.notificationDays),
    );

    return NotificationSettings(
      enabled: p.getBool(StorageKeys.notificationEnabled) ?? false,
      keywords: keywords,
      alertTimes: alertTimes,
      rememberedTimes: remembered,
      cafeterias: cafeterias,
      dormMealTypes: dormMealTypes,
      days: days,
    );
  }

  static ThemeMode _loadThemeMode(SharedPreferences p) =>
      ThemeMode.values.asNameMap()[p.getString(StorageKeys.themeMode)] ??
      ThemeMode.system;

  // --- 시간 문자열 파싱/포매팅 헬퍼 ---

  static String _formatTime(TimeOfDay t) => '${t.hour}:${t.minute}';

  static TimeOfDay? _parseTime(String s) {
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static bool _isWithinPeriodSlots(MealAlertPeriod period, TimeOfDay t) =>
      period.allSlots.any((s) => s.hour == t.hour && s.minute == t.minute);

  /// 구버전 시각이 어느 시간대 범위(그리고 15분 슬롯)에 매칭되는지 찾는다.
  /// 매칭되는 것이 없으면 null.
  static (MealAlertPeriod, TimeOfDay)? _snapLegacyTime(TimeOfDay t) {
    for (final period in MealAlertPeriod.values) {
      if (_isWithinPeriodSlots(period, t)) return (period, t);
    }
    return null;
  }
}
