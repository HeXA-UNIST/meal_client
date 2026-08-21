import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'allergy/allergy_settings.dart';
import 'notification/notification_settings.dart';
import 'notification/notification_settings_store.dart';

typedef NotificationAuthorizationStatusReader =
    Future<MealNotificationAuthorizationStatus> Function();
typedef AppResumeListenerRegistrar =
    VoidCallback Function(VoidCallback onResume);
typedef ForegroundMealRefresher =
    Future<void> Function(DateTime now, bool waitForNextWeekPrefetch);
typedef MealCacheRevisionSnapshot = ({
  MealCacheRevision? current,
  MealCacheRevision? next,
});
typedef MealCacheRevisionSnapshotReader =
    Future<MealCacheRevisionSnapshot> Function();

const foregroundMealRefreshInterval = Duration(hours: 1);

class AppSettings extends ChangeNotifier {
  final SharedPreferences _prefs;

  AllergySettings _allergy;
  NotificationSettings _notification;
  ThemeMode _themeMode;
  final NotificationScheduleCoordinator _notificationScheduleCoordinator;
  final Future<bool> Function() _requestNotificationPermission;
  final NotificationAuthorizationStatusReader _readAuthorizationStatus;
  final MealNotificationPlatform _notificationPlatform;
  final DateTime Function() _clock;
  final ForegroundMealRefresher _refreshForegroundMeal;
  final MealCacheRevisionSnapshotReader _readMealCacheRevisions;
  VoidCallback? _disposeResumeListener;
  ({String? current, String? next})? _observedCacheContent;
  Future<void> _notificationGenerationQueue = Future.value();
  bool _disposed = false;
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
    MealNotificationPlatform? notificationPlatform,
    AppResumeListenerRegistrar? resumeListenerRegistrar,
    DateTime Function()? clock,
    ForegroundMealRefresher? foregroundMealRefresher,
    MealCacheRevisionSnapshotReader? mealCacheRevisionSnapshotReader,
  }) : _notificationScheduleCoordinator =
           notificationScheduleCoordinator ?? NotificationScheduleCoordinator(),
       _requestNotificationPermission =
           notificationPermissionRequester ?? requestNotificationPermission,
       _readAuthorizationStatus =
           notificationAuthorizationStatusReader ??
           mealNotificationAuthorizationStatus,
       _notificationPlatform = notificationPlatform ?? mealNotificationPlatform,
       _clock = clock ?? DateTime.now,
       _refreshForegroundMeal =
           foregroundMealRefresher ?? _defaultForegroundMealRefresh,
       _readMealCacheRevisions =
           mealCacheRevisionSnapshotReader ?? _defaultMealCacheRevisionSnapshot,
       _allergy = _loadAllergy(_prefs),
       _notification = loadNotificationSettings(_prefs),
       _themeMode = _loadThemeMode(_prefs) {
    if (_notificationPlatform == MealNotificationPlatform.ios) {
      _disposeResumeListener =
          (resumeListenerRegistrar ?? _registerResumeListener)(
            () => unawaited(
              _handleAppResume().catchError((Object error, StackTrace stack) {
                debugPrint(
                  '[BapU] app resume notification refresh failed: $error',
                );
                debugPrintStack(stackTrace: stack);
              }),
            ),
          );
    }
  }

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
    final persistence = _prefs.setBool(StorageKeys.notificationEnabled, v);
    notifyListeners();
    await persistence;
    if (_disposed) return false;
    if (v) {
      await _runNotificationReschedule(immediately: true);
    } else {
      await _runCancelAllMealNotifications();
    }
    return true;
  }

  /// 앱 시작 시 현재 알림 설정을 플랫폼 예약 방식에 반영한다.
  void rescheduleMealNotifications() {
    if (_notification.enabled) {
      unawaited(_reconcileFromCache());
    }
  }

  /// foreground 식단 갱신이 cache 내용을 바꿨을 때만 iOS 예약을 다시 만든다.
  void reconcileIosMealNotificationsAfterForegroundRefresh() {
    if (_notificationPlatform != MealNotificationPlatform.ios ||
        !_notification.enabled) {
      return;
    }
    unawaited(_reconcileChangedForegroundMeal());
  }

  Future<void> _handleAppResume() async {
    if (_disposed) return;
    if (_notification.enabled ||
        _notificationAuthorizationStatus ==
            MealNotificationAuthorizationStatus.notAuthorized) {
      await refreshNotificationAuthorizationStatus();
    }
    if (_disposed || !_notification.enabled) return;
    await _reconcileFromCache(refreshAuthorization: false);
    if (_disposed) return;
    await _performForegroundMealRefresh();
  }

  Future<void> _reconcileFromCache({bool refreshAuthorization = true}) async {
    if (_disposed || !_notification.enabled) return;
    if (refreshAuthorization) {
      await refreshNotificationAuthorizationStatus();
    }
    if (_disposed) return;
    if (_notificationPlatform == MealNotificationPlatform.ios) {
      _rememberCacheContent(await _readMealCacheRevisions());
    }
    if (_disposed) return;
    await _runNotificationReschedule(immediately: true);
  }

  Future<void> _reconcileChangedForegroundMeal() async {
    final revisions = await _readMealCacheRevisions();
    if (_disposed) return;
    final isFirstObservation = _observedCacheContent == null;
    if (!_rememberCacheContent(revisions) && !isFirstObservation) return;
    await _runNotificationReschedule(immediately: true);
  }

  Future<void> _performForegroundMealRefresh() async {
    try {
      final now = _clock();
      final before = await _readMealCacheRevisions();
      if (_disposed) return;
      final currentUpdatedAt = before.current?.updatedAt;
      final currentIsFresh =
          currentUpdatedAt != null &&
          _revisionTargetsWeek(before.current!, kstWeekStartForInstant(now)) &&
          now.difference(currentUpdatedAt) <= foregroundMealRefreshInterval;
      final needsSundayTopUp = _needsSundayNextWeekTopUp(before.next, now);
      if (currentIsFresh && !needsSundayTopUp) return;

      await _refreshForegroundMeal(now, needsSundayTopUp);
      if (_disposed) return;
      final after = await _readMealCacheRevisions();
      if (_disposed) return;
      if (_rememberCacheContent(after)) {
        await _runNotificationReschedule(immediately: true);
      }
    } catch (error, stackTrace) {
      debugPrint('[BapU] foreground meal refresh on resume failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  bool _rememberCacheContent(MealCacheRevisionSnapshot revisions) {
    final next = (
      current: revisions.current?.rawMeal,
      next: revisions.next?.rawMeal,
    );
    final changed =
        _observedCacheContent != null && _observedCacheContent != next;
    _observedCacheContent = next;
    return changed;
  }

  /// 외부 설정에서 바뀐 iOS 권한 상태를 설정 화면에 반영한다.
  Future<void> refreshNotificationAuthorizationStatus() async {
    final status = await _readAuthorizationStatus();
    if (_disposed ||
        (!_notification.enabled &&
            _notificationAuthorizationStatus !=
                MealNotificationAuthorizationStatus.notAuthorized) ||
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
    final persistence = _prefs.setStringList(
      StorageKeys.notificationKeywords,
      next,
    );
    notifyListeners();
    if (_notification.enabled) {
      _rescheduleAfterPersistence(persistence);
    } else {
      unawaited(persistence);
    }
  }

  void removeNotificationKeyword(String kw) {
    if (!_notification.keywords.contains(kw)) return;
    final next = _notification.keywords.where((k) => k != kw).toList();
    _notification = _notification.copyWith(keywords: next);
    final persistence = _prefs.setStringList(
      StorageKeys.notificationKeywords,
      next,
    );
    notifyListeners();
    if (_notification.enabled) {
      _rescheduleAfterPersistence(persistence);
    } else {
      unawaited(persistence);
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
    final Future<bool> persistence;
    if (time == null) {
      persistence = _prefs.remove(key);
    } else {
      persistence = Future.wait([
        _prefs.setString(key, _formatTime(time)),
        _prefs.setString(
          '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
          _formatTime(time),
        ),
      ]).then((results) => results.every((result) => result));
    }
    notifyListeners();

    if (_notification.enabled) {
      _rescheduleAfterPersistence(persistence);
    } else {
      unawaited(persistence);
    }
  }

  /// 학생·교직원 식당 알림 대상을 설정한다. 기숙사 식당은 여기서 다루지 않고
  /// [setNotificationDormMealTypes]가 전담한다 (진실 공급원을 하나로 유지).
  void setNotificationCafeterias(Set<Cafeteria> cafeterias) {
    final filtered = cafeterias.where((c) => c != Cafeteria.dormitory).toSet();
    _notification = _notification.copyWith(cafeterias: filtered);
    final persistence = _prefs.setStringList(
      StorageKeys.notificationCafeterias,
      filtered.map((e) => e.name).toList(),
    );
    notifyListeners();
    if (_notification.enabled) {
      _rescheduleAfterPersistence(persistence);
    } else {
      unawaited(persistence);
    }
  }

  /// 기숙사 식당 알림 대상 메뉴 종류(한식/할랄)를 설정한다.
  /// 이 값이 비어있으면 기숙사 식당 자체가 알림 대상에서 빠진 것으로 취급된다.
  void setNotificationDormMealTypes(Set<DormMealType> types) {
    _notification = _notification.copyWith(dormMealTypes: types);
    final persistence = _prefs.setStringList(
      StorageKeys.notificationDormMealTypes,
      types.map((e) => e.name).toList(),
    );
    notifyListeners();
    if (_notification.enabled) {
      _rescheduleAfterPersistence(persistence);
    } else {
      unawaited(persistence);
    }
  }

  /// 알림을 받을 요일 집합을 설정하고, 다음 활성 메뉴 요일로 다시 예약한다.
  void setNotificationDays(Set<DayOfWeek> days) {
    _notification = _notification.copyWith(days: days);
    final persistence = _prefs.setStringList(
      StorageKeys.notificationDays,
      days.map((e) => e.name).toList(),
    );
    notifyListeners();
    if (_notification.enabled) {
      _rescheduleAfterPersistence(persistence);
    } else {
      unawaited(persistence);
    }
  }

  void _rescheduleAfterPersistence(Future<bool> persistence) {
    unawaited(
      (() async {
        await persistence;
        if (_disposed || !_notification.enabled) return;
        await _runNotificationReschedule();
      })(),
    );
  }

  Future<NotificationScheduleOutcome> _runNotificationReschedule({
    bool immediately = false,
  }) async {
    await _advanceNotificationMutationGeneration();
    if (_disposed) return NotificationScheduleOutcome.disposed;
    return (immediately
            ? _notificationScheduleCoordinator.scheduleNow(_notification)
            : _notificationScheduleCoordinator.schedule(_notification))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[BapU] meal notification reconciliation failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          return NotificationScheduleOutcome.canceled;
        });
  }

  Future<void> _runCancelAllMealNotifications() async {
    await _advanceNotificationMutationGeneration();
    if (_disposed) return;
    await _notificationScheduleCoordinator.cancelAll().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      debugPrint('[BapU] meal notification cancellation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    });
  }

  Future<void> _advanceNotificationMutationGeneration() {
    if (_notificationPlatform != MealNotificationPlatform.ios) {
      return Future.value();
    }
    final operation = _notificationGenerationQueue.then((_) async {
      final next =
          (_prefs.getInt(StorageKeys.notificationMutationGeneration) ?? 0) + 1;
      await _prefs.setInt(StorageKeys.notificationMutationGeneration, next);
    });
    _notificationGenerationQueue = operation.then<void>(
      (_) {},
      onError: (_, _) {},
    );
    return operation;
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
    final persistence = <Future<bool>>[
      _prefs.setStringList(StorageKeys.allergenIds, []),
      _prefs.setBool(StorageKeys.notificationEnabled, false),
      _prefs.setStringList(StorageKeys.notificationKeywords, []),
    ];
    for (final period in MealNotificationPeriod.values) {
      persistence.addAll([
        _prefs.remove(
          '${StorageKeys.notificationPeriodTimePrefix}${period.name}',
        ),
        _prefs.remove(
          '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
        ),
      ]);
    }
    persistence.addAll([
      _prefs.remove(StorageKeys.notificationCafeterias),
      _prefs.remove(StorageKeys.notificationDormMealTypes),
      _prefs.remove(StorageKeys.notificationDays),
      _prefs.setString(StorageKeys.themeMode, ThemeMode.system.name),
    ]);
    notifyListeners();
    unawaited(_finishReset(persistence));
  }

  Future<void> _finishReset(List<Future<bool>> persistence) async {
    await Future.wait(persistence);
    if (_disposed) return;
    await _runCancelAllMealNotifications();
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeResumeListener?.call();
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

VoidCallback _registerResumeListener(VoidCallback onResume) {
  final listener = AppLifecycleListener(onResume: onResume);
  return listener.dispose;
}

Future<void> _defaultForegroundMealRefresh(
  DateTime now,
  bool waitForNextWeekPrefetch,
) async {
  await fetchAndCacheCanonicalMealData(
    now: now,
    waitForNextWeekPrefetch: waitForNextWeekPrefetch,
  );
}

Future<MealCacheRevisionSnapshot> _defaultMealCacheRevisionSnapshot() async => (
  current: await MealCache().readRevision(),
  next: await MealCache(fileName: StorageKeys.nextMealCacheFile).readRevision(),
);

bool _needsSundayNextWeekTopUp(MealCacheRevision? revision, DateTime now) {
  final nowKst = MealTimeConfig.toKst(now);
  if (nowKst.weekday != DateTime.sunday) return false;
  final expectedWeek = kstWeekStartForInstant(now).add(const Duration(days: 7));
  if (revision == null || !_revisionTargetsWeek(revision, expectedWeek)) {
    return true;
  }
  final writtenAt = revision.updatedAt;
  final writtenKst = MealTimeConfig.toKst(writtenAt);
  return writtenKst.year != nowKst.year ||
      writtenKst.month != nowKst.month ||
      writtenKst.day != nowKst.day;
}

bool _revisionTargetsWeek(MealCacheRevision revision, DateTime expectedWeek) {
  try {
    final actual = parseWeekMeta(revision.rawMeal).startDate;
    return actual.year == expectedWeek.year &&
        actual.month == expectedWeek.month &&
        actual.day == expectedWeek.day;
  } on FormatException {
    return false;
  }
}
