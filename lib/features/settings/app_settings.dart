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
typedef NotificationPersistenceRunner =
    Future<bool> Function(Future<bool> Function() write);

const foregroundMealRefreshInterval = Duration(hours: 1);

enum NotificationEnableResult { enabled, permissionDenied, failed }

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
  final NotificationPersistenceRunner _runNotificationPersistence;
  VoidCallback? _disposeResumeListener;
  ({String? current, String? next})? _observedCacheContent;
  Future<void> _notificationMutationQueue = Future.value();
  bool _disposed = false;
  MealNotificationAuthorizationStatus? _notificationAuthorizationStatus;
  bool _notificationSyncFailed = false;
  int _authorizationRefreshRevision = 0;

  AllergySettings get allergy => _allergy;
  NotificationSettings get notification => _notification;
  ThemeMode get themeMode => _themeMode;
  MealNotificationAuthorizationStatus? get notificationAuthorizationStatus =>
      _notificationAuthorizationStatus;
  bool get notificationSyncFailed => _notificationSyncFailed;
  bool get usesInexactNotificationTiming =>
      _notificationPlatform == MealNotificationPlatform.android;

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
    NotificationPersistenceRunner? notificationPersistenceRunner,
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
       _runNotificationPersistence =
           notificationPersistenceRunner ?? _defaultNotificationPersistence,
       _allergy = _loadAllergy(_prefs),
       _notification = loadNotificationSettings(_prefs),
       _themeMode = _loadThemeMode(_prefs) {
    if (_notificationPlatform != MealNotificationPlatform.unsupported) {
      _disposeResumeListener =
          (resumeListenerRegistrar ?? _registerResumeListener)(
            () => unawaited(
              _handleAppResume().catchError((Object error, StackTrace stack) {
                _setNotificationSyncFailed(true);
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

  Future<NotificationEnableResult> setNotificationEnabled(bool v) async {
    return _enqueueNotificationMutation(() async {
      if (_disposed) return NotificationEnableResult.failed;
      _authorizationRefreshRevision++;
      final previousAuthorizationStatus = _notificationAuthorizationStatus;
      if (v) {
        final granted = await _requestNotificationPermission();
        if (_disposed) return NotificationEnableResult.failed;
        _notificationAuthorizationStatus = granted
            ? MealNotificationAuthorizationStatus.enabled
            : MealNotificationAuthorizationStatus.notAuthorized;
        if (!granted) {
          notifyListeners();
          return NotificationEnableResult.permissionDenied;
        }
      } else {
        _notificationAuthorizationStatus = null;
      }

      final applied = await _applyNotificationMutation(
        next: _notification.copyWith(enabled: v),
        persist: () => _prefs.setBool(StorageKeys.notificationEnabled, v),
        immediately: true,
        rollbackOnSyncFailure: v,
        rollbackPersist: () => _prefs.setBool(
          StorageKeys.notificationEnabled,
          _notification.enabled,
        ),
      );
      if (!applied) {
        _notificationAuthorizationStatus = previousAuthorizationStatus;
        notifyListeners();
        return NotificationEnableResult.failed;
      }
      return NotificationEnableResult.enabled;
    });
  }

  /// 앱 시작 시 현재 알림 설정을 플랫폼 예약 방식에 반영한다.
  void rescheduleMealNotifications() {
    if (_notification.enabled) {
      _runUnawaitedNotificationOperation(
        _enqueueNotificationMutation(_reconcileFromCache),
        'app launch reconciliation',
      );
    }
  }

  /// foreground 식단 갱신이 cache 내용을 바꿨을 때만 네이티브 예약을 다시 만든다.
  void reconcileMealNotificationsAfterForegroundRefresh() {
    if (_notificationPlatform == MealNotificationPlatform.unsupported ||
        !_notification.enabled) {
      return;
    }
    _runUnawaitedNotificationOperation(
      _enqueueNotificationMutation(_reconcileChangedForegroundMeal),
      'foreground cache reconciliation',
    );
  }

  Future<void> _handleAppResume() async {
    if (_disposed) return;
    await refreshNotificationAuthorizationStatus();
    if (_disposed || !_notification.enabled) return;
    await _enqueueNotificationMutation(
      () => _reconcileFromCache(refreshAuthorization: false),
    );
    if (_disposed) return;
    await _performForegroundMealRefresh();
  }

  /// 앱 launch/resume 공통 재조정 진입점이다. Android 재부팅 복구 정책은
  /// `AndroidManifest.xml`의 `ScheduledNotificationReceiver` 주석을 따른다.
  Future<void> _reconcileFromCache({bool refreshAuthorization = true}) async {
    if (_disposed || !_notification.enabled) return;
    if (refreshAuthorization) {
      await refreshNotificationAuthorizationStatus();
    }
    if (_disposed) return;
    if (_notificationPlatform != MealNotificationPlatform.unsupported) {
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
        try {
          await _enqueueNotificationMutation(
            () => _runNotificationReschedule(immediately: true),
          );
        } catch (error, stackTrace) {
          _setNotificationSyncFailed(true);
          debugPrint(
            '[BapU] foreground cache notification reconciliation failed: $error',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
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

  /// 외부 설정에서 바뀐 네이티브 권한 상태를 설정 화면에 반영한다.
  Future<void> refreshNotificationAuthorizationStatus() async {
    final revision = ++_authorizationRefreshRevision;
    final status = await _readAuthorizationStatus();
    if (_disposed ||
        revision != _authorizationRefreshRevision ||
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
    unawaited(
      _enqueueNotificationMutation(() async {
        if (_notification.keywords.contains(trimmed)) return;
        final keywords = [..._notification.keywords, trimmed];
        await _applyNotificationMutation(
          next: _notification.copyWith(keywords: keywords),
          persist: () =>
              _prefs.setStringList(StorageKeys.notificationKeywords, keywords),
        );
      }),
    );
  }

  void removeNotificationKeyword(String kw) {
    unawaited(
      _enqueueNotificationMutation(() async {
        if (!_notification.keywords.contains(kw)) return;
        final keywords = _notification.keywords
            .where((keyword) => keyword != kw)
            .toList();
        await _applyNotificationMutation(
          next: _notification.copyWith(keywords: keywords),
          persist: () =>
              _prefs.setStringList(StorageKeys.notificationKeywords, keywords),
        );
      }),
    );
  }

  /// [time]이 null이면 해당 시간대 알림을 끈다(마지막 선택 시각은 기억해 둔다).
  /// 그렇지 않으면 해당 시간대에 지정 시각으로 알림을 등록한다.
  void setPeriodAlertTime(MealNotificationPeriod period, TimeOfDay? time) {
    unawaited(
      _enqueueNotificationMutation(() async {
        final alertTimes = Map<MealNotificationPeriod, TimeOfDay?>.from(
          _notification.alertTimes,
        );
        final rememberedTimes = Map<MealNotificationPeriod, TimeOfDay>.from(
          _notification.rememberedTimes,
        );
        if (time == null) {
          alertTimes.remove(period);
        } else {
          alertTimes[period] = time;
          rememberedTimes[period] = time;
        }
        final key = '${StorageKeys.notificationPeriodTimePrefix}${period.name}';
        await _applyNotificationMutation(
          next: _notification.copyWith(
            alertTimes: alertTimes,
            rememberedTimes: rememberedTimes,
          ),
          persist: () => time == null
              ? _prefs.remove(key)
              : Future.wait([
                  _prefs.setString(key, _formatTime(time)),
                  _prefs.setString(
                    '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
                    _formatTime(time),
                  ),
                ]).then((results) => results.every((result) => result)),
        );
      }),
    );
  }

  /// 학생·교직원 식당 알림 대상을 설정한다. 기숙사 식당은 여기서 다루지 않고
  /// [setNotificationDormMealTypes]가 전담한다 (진실 공급원을 하나로 유지).
  void setNotificationCafeterias(Set<Cafeteria> cafeterias) {
    final filtered = cafeterias.where((c) => c != Cafeteria.dormitory).toSet();
    unawaited(
      _enqueueNotificationMutation(
        () => _applyNotificationMutation(
          next: _notification.copyWith(cafeterias: filtered),
          persist: () => _prefs.setStringList(
            StorageKeys.notificationCafeterias,
            filtered.map((cafeteria) => cafeteria.name).toList(),
          ),
        ),
      ),
    );
  }

  /// 기숙사 식당 알림 대상 메뉴 종류(한식/할랄)를 설정한다.
  /// 이 값이 비어있으면 기숙사 식당 자체가 알림 대상에서 빠진 것으로 취급된다.
  void setNotificationDormMealTypes(Set<DormMealType> types) {
    final snapshot = Set<DormMealType>.from(types);
    unawaited(
      _enqueueNotificationMutation(
        () => _applyNotificationMutation(
          next: _notification.copyWith(dormMealTypes: snapshot),
          persist: () => _prefs.setStringList(
            StorageKeys.notificationDormMealTypes,
            snapshot.map((type) => type.name).toList(),
          ),
        ),
      ),
    );
  }

  /// 알림을 받을 요일 집합을 설정하고, 다음 활성 메뉴 요일로 다시 예약한다.
  void setNotificationDays(Set<DayOfWeek> days) {
    final snapshot = Set<DayOfWeek>.from(days);
    unawaited(
      _enqueueNotificationMutation(
        () => _applyNotificationMutation(
          next: _notification.copyWith(days: snapshot),
          persist: () => _prefs.setStringList(
            StorageKeys.notificationDays,
            snapshot.map((day) => day.name).toList(),
          ),
        ),
      ),
    );
  }

  Future<bool> _applyNotificationMutation({
    required NotificationSettings next,
    required Future<bool> Function() persist,
    bool immediately = false,
    bool rollbackOnSyncFailure = false,
    Future<bool> Function()? rollbackPersist,
  }) async {
    final previous = _notification;
    _notification = next;
    notifyListeners();
    try {
      final persisted = await _runNotificationPersistence(persist);
      if (!persisted) {
        throw StateError('Notification preferences write failed');
      }
    } catch (error, stackTrace) {
      _notification = previous;
      if (!_disposed) {
        _notificationSyncFailed = true;
        notifyListeners();
      }
      debugPrint('[BapU] notification persistence failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }

    try {
      if (_disposed) return false;
      if (next.enabled) {
        await _runNotificationReschedule(immediately: immediately);
      } else {
        await _runCancelAllMealNotifications();
      }
      _setNotificationSyncFailed(false);
      return true;
    } catch (error, stackTrace) {
      if (rollbackOnSyncFailure) {
        _notification = previous;
        if (rollbackPersist != null) {
          try {
            final restored = await _runNotificationPersistence(rollbackPersist);
            if (!restored) {
              throw StateError('Notification preference rollback failed');
            }
          } catch (rollbackError, rollbackStackTrace) {
            debugPrint(
              '[BapU] notification persistence rollback failed: $rollbackError',
            );
            debugPrintStack(stackTrace: rollbackStackTrace);
          }
        }
        try {
          await _runCancelAllMealNotifications();
        } catch (cleanupError, cleanupStackTrace) {
          debugPrint(
            '[BapU] failed enable notification cleanup failed: $cleanupError',
          );
          debugPrintStack(stackTrace: cleanupStackTrace);
        }
      }
      _setNotificationSyncFailed(true);
      debugPrint('[BapU] notification synchronization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<T> _enqueueNotificationMutation<T>(Future<T> Function() operation) {
    final queued = _notificationMutationQueue.then<T>((_) => operation());
    _notificationMutationQueue = queued.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return queued;
  }

  Future<NotificationScheduleOutcome> _runNotificationReschedule({
    bool immediately = false,
  }) async {
    await _advanceNotificationMutationGeneration();
    if (_disposed) return NotificationScheduleOutcome.disposed;
    final outcome = immediately
        ? await _notificationScheduleCoordinator.scheduleNow(_notification)
        : await _notificationScheduleCoordinator.schedule(_notification);
    if (outcome == NotificationScheduleOutcome.scheduled) {
      _setNotificationSyncFailed(false);
    }
    return outcome;
  }

  Future<void> _runCancelAllMealNotifications() async {
    await _advanceNotificationMutationGeneration();
    if (_disposed) return;
    await _notificationScheduleCoordinator.cancelAll();
    _setNotificationSyncFailed(false);
  }

  /// 실패한 저장·예약을 현재 화면의 설정 스냅샷으로 한 번 다시 적용한다.
  Future<bool> retryNotificationSync() =>
      _enqueueNotificationMutation(() async {
        if (_disposed) return false;
        try {
          final persisted = await _runNotificationPersistence(
            () => _persistNotificationSnapshot(_notification),
          );
          if (!persisted) {
            throw StateError('Notification preferences write failed');
          }
          if (_notification.enabled) {
            await _runNotificationReschedule(immediately: true);
          } else {
            await _runCancelAllMealNotifications();
          }
          _setNotificationSyncFailed(false);
          return true;
        } catch (error, stackTrace) {
          _setNotificationSyncFailed(true);
          debugPrint('[BapU] notification retry failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          return false;
        }
      });

  Future<bool> _persistNotificationSnapshot(
    NotificationSettings settings,
  ) async {
    final writes = <Future<bool>>[
      _prefs.setBool(StorageKeys.notificationEnabled, settings.enabled),
      _prefs.setStringList(StorageKeys.notificationKeywords, settings.keywords),
      _prefs.setStringList(
        StorageKeys.notificationCafeterias,
        settings.cafeterias.map((cafeteria) => cafeteria.name).toList(),
      ),
      _prefs.setStringList(
        StorageKeys.notificationDormMealTypes,
        settings.dormMealTypes.map((type) => type.name).toList(),
      ),
      _prefs.setStringList(
        StorageKeys.notificationDays,
        settings.days.map((day) => day.name).toList(),
      ),
    ];
    for (final period in MealNotificationPeriod.values) {
      final alertTime = settings.alertTimeOf(period);
      writes.add(
        alertTime == null
            ? _prefs.remove(
                '${StorageKeys.notificationPeriodTimePrefix}${period.name}',
              )
            : _prefs.setString(
                '${StorageKeys.notificationPeriodTimePrefix}${period.name}',
                _formatTime(alertTime),
              ),
      );
      final rememberedTime = settings.rememberedTimes[period];
      writes.add(
        rememberedTime == null
            ? _prefs.remove(
                '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
              )
            : _prefs.setString(
                '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
                _formatTime(rememberedTime),
              ),
      );
    }
    return (await Future.wait(writes)).every((result) => result);
  }

  void _setNotificationSyncFailed(bool failed) {
    if (_disposed || _notificationSyncFailed == failed) return;
    _notificationSyncFailed = failed;
    notifyListeners();
  }

  Future<void> _advanceNotificationMutationGeneration() async {
    if (_notificationPlatform == MealNotificationPlatform.unsupported) {
      return;
    }
    final next =
        (_prefs.getInt(StorageKeys.notificationMutationGeneration) ?? 0) + 1;
    final persisted = await _runNotificationPersistence(
      () => _prefs.setInt(StorageKeys.notificationMutationGeneration, next),
    );
    if (!persisted) {
      throw StateError('Notification generation write failed');
    }
  }

  void _runUnawaitedNotificationOperation(
    Future<void> operation,
    String label,
  ) {
    unawaited(
      operation.catchError((Object error, StackTrace stackTrace) {
        _setNotificationSyncFailed(true);
        debugPrint('[BapU] $label failed: $error');
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
    _themeMode = ThemeMode.system;
    unawaited(_prefs.setStringList(StorageKeys.allergenIds, []));
    unawaited(_prefs.setString(StorageKeys.themeMode, ThemeMode.system.name));
    notifyListeners();
    unawaited(
      _enqueueNotificationMutation(() async {
        final previousAuthorizationStatus = _notificationAuthorizationStatus;
        _notificationAuthorizationStatus = null;
        final applied = await _applyNotificationMutation(
          next: _notification.reset(),
          persist: () async {
            final writes = <Future<bool>>[
              _prefs.setBool(StorageKeys.notificationEnabled, false),
              _prefs.setStringList(StorageKeys.notificationKeywords, []),
              _prefs.remove(StorageKeys.notificationCafeterias),
              _prefs.remove(StorageKeys.notificationDormMealTypes),
              _prefs.remove(StorageKeys.notificationDays),
            ];
            for (final period in MealNotificationPeriod.values) {
              writes.addAll([
                _prefs.remove(
                  '${StorageKeys.notificationPeriodTimePrefix}${period.name}',
                ),
                _prefs.remove(
                  '${StorageKeys.notificationPeriodRememberedPrefix}${period.name}',
                ),
              ]);
            }
            return (await Future.wait(writes)).every((result) => result);
          },
          immediately: true,
        );
        if (!applied) {
          _notificationAuthorizationStatus = previousAuthorizationStatus;
          notifyListeners();
        }
      }),
    );
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

Future<bool> _defaultNotificationPersistence(Future<bool> Function() write) =>
    write();

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
