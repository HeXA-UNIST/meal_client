import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/firebase_options.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/features/settings/notification/notification_settings_store.dart';
import 'package:meal_client/features/widget/widget_service.dart';
import 'meal_notification_mutation_lock.dart';
import 'notification_platform.dart';
import 'notification_service.dart';
import 'scheduled_meal_notifications.dart';

typedef BackgroundCacheRefresh = Future<void> Function();
typedef BackgroundNotificationReconcile = Future<void> Function();
typedef BackgroundErrorReporter =
    Future<void> Function(String stage, Object error, StackTrace stackTrace);
typedef BackgroundNotificationSnapshot = ({
  NotificationSettings settings,
  int generation,
  String? currentRevision,
  String? nextRevision,
});
typedef BackgroundNotificationSnapshotLoader =
    Future<BackgroundNotificationSnapshot> Function();

/// Workmanager 백그라운드 격리체(isolate) 진입점.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    if (taskName == mealRefreshTaskName ||
        taskName == Workmanager.iOSBackgroundTask) {
      BackgroundErrorReporter? reportError;
      if (kReleaseMode &&
          mealNotificationPlatform == MealNotificationPlatform.android) {
        try {
          // Workmanager 격리체에는 main의 Firebase 초기화가 적용되지 않는다.
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          reportError = (stage, error, stack) =>
              FirebaseCrashlytics.instance.recordError(
                error,
                stack,
                reason: 'background_$stage',
                fatal: false,
              );
        } catch (error, stack) {
          // 진단 초기화 실패와 무관하게 실제 갱신 작업은 수행한다.
          debugPrint(
            '[BapU] background Firebase initialization failed: $error',
          );
          debugPrintStack(stackTrace: stack);
        }
      }
      return refreshBackgroundMealAndInfoCaches(reportError: reportError);
    }

    return true;
  });
}

Future<bool> refreshBackgroundMealAndInfoCaches({
  BackgroundCacheRefresh? refreshMealCache,
  BackgroundCacheRefresh? refreshInfoCache,
  BackgroundCacheRefresh? refreshWidget,
  BackgroundNotificationReconcile? reconcileNotifications,
  MealNotificationPlatform? platform,
  BackgroundErrorReporter? reportError,
}) async {
  final mealRefresh =
      refreshMealCache ??
      () async {
        await MealRefreshService(
          throwOnCacheWriteFailure: true,
        ).refreshMealData(waitForNextWeekPrefetch: true);
      };
  final infoRefresh =
      refreshInfoCache ??
      () async {
        await InfoRefreshService(throwOnCacheWriteFailure: true).refreshInfo();
      };

  final failures = await Future.wait([
    _captureBackgroundRefreshFailure('meal', mealRefresh, reportError),
    _captureBackgroundRefreshFailure('info', infoRefresh, reportError),
  ]);

  final mealFailure = failures[0];
  if (mealFailure != null) {
    _logBackgroundRefreshFailure('background meal refresh failed', mealFailure);
    return false;
  }

  final infoFailure = failures[1];
  if (infoFailure != null) {
    if (infoFailure.error is InfoCacheWriteException) {
      _logBackgroundRefreshFailure(
        'background info cache write failed',
        infoFailure,
      );
      return false;
    }

    // develop-widget 병합 시에도 notification 브랜치의 기준은 유지한다.
    // meal cache 갱신이 끝난 뒤 /v2/info fetch/parse 실패만으로는 키워드 알림용
    // background task를 실패시키지 않는다. 공유 cache write 실패만 strict 처리한다.
    _logBackgroundRefreshFailure(
      'background info refresh skipped',
      infoFailure,
    );
  }

  final widgetFailure = await _captureBackgroundRefreshFailure(
    'widget',
    refreshWidget ?? () => refreshWidgets(throwOnFailure: true),
    reportError,
  );
  if (widgetFailure != null) {
    _logBackgroundRefreshFailure(
      'background widget refresh failed',
      widgetFailure,
    );
    return false;
  }

  final currentPlatform = platform ?? mealNotificationPlatform;
  final notificationFailure =
      currentPlatform != MealNotificationPlatform.unsupported
      ? await _captureBackgroundRefreshFailure(
          'notification',
          reconcileNotifications ?? _reconcileNotificationsFromCache,
          reportError,
        )
      : null;

  if (notificationFailure != null) {
    _logBackgroundRefreshFailure(
      'background meal notification reconciliation failed',
      notificationFailure,
    );
    return false;
  }

  return true;
}

Future<void> _reconcileNotificationsFromCache() async {
  await initNotifications();
  await reconcileBackgroundMealNotifications();
}

Future<void> reconcileBackgroundMealNotifications({
  BackgroundNotificationSnapshotLoader? loadSnapshot,
  Future<void> Function(NotificationSettings settings)? reconcile,
  Future<void> Function()? cancelPending,
  MealNotificationMutationSection? mutationSection,
}) => (mutationSection ?? withMealNotificationMutationLock)(() async {
  final snapshotLoader = loadSnapshot ?? _loadFreshNotificationSnapshot;
  var snapshot = await snapshotLoader();
  for (var attempt = 0; attempt < 3; attempt++) {
    if (snapshot.settings.enabled) {
      await (reconcile ??
          (settings) => reconcileScheduledMealNotifications(
            settings: settings,
          ))(snapshot.settings);
    } else {
      await (cancelPending ?? cancelAllPendingMealNotifications)();
    }

    final after = await snapshotLoader();
    if (_sameBackgroundSnapshot(snapshot, after)) return;
    snapshot = after;
  }
  throw StateError('Native notification inputs did not stabilize');
});

Future<BackgroundNotificationSnapshot> _loadFreshNotificationSnapshot() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return (
    settings: loadNotificationSettings(prefs),
    generation: prefs.getInt(StorageKeys.notificationMutationGeneration) ?? 0,
    currentRevision: (await MealCache().readRevision())?.rawMeal,
    nextRevision: (await MealCache(
      fileName: StorageKeys.nextMealCacheFile,
    ).readRevision())?.rawMeal,
  );
}

bool _sameBackgroundSnapshot(
  BackgroundNotificationSnapshot first,
  BackgroundNotificationSnapshot second,
) =>
    first.generation == second.generation &&
    first.currentRevision == second.currentRevision &&
    first.nextRevision == second.nextRevision &&
    _notificationSettingsFingerprint(first.settings) ==
        _notificationSettingsFingerprint(second.settings);

String _notificationSettingsFingerprint(NotificationSettings settings) {
  final alertTimes =
      settings.alertTimes.entries
          .map(
            (entry) =>
                '${entry.key.name}:${entry.value?.hour}:${entry.value?.minute}',
          )
          .toList()
        ..sort();
  final cafeterias = settings.cafeterias.map((item) => item.name).toList()
    ..sort();
  final dormTypes = settings.dormMenuTypes.map((item) => item.name).toList()
    ..sort();
  final days = settings.days.map((item) => item.name).toList()..sort();
  return [
    settings.enabled,
    alertTimes.join(','),
    settings.keywords.join('\u0000'),
    cafeterias.join(','),
    dormTypes.join(','),
    days.join(','),
  ].join('|');
}

Future<_BackgroundRefreshFailure?> _captureBackgroundRefreshFailure(
  String label,
  BackgroundCacheRefresh refresh,
  BackgroundErrorReporter? reportError,
) async {
  try {
    await refresh();
    return null;
  } catch (e, stackTrace) {
    try {
      // 병렬 갱신의 다른 실패나 조기 반환 때문에 보고가 누락되지 않게 한다.
      await reportError?.call(label, e, stackTrace);
    } catch (reportingError, reportingStack) {
      // 보고 실패로 원래 작업의 성공 여부나 재시도 판단을 바꾸지 않는다.
      debugPrint('[BapU] background error reporting failed: $reportingError');
      debugPrintStack(stackTrace: reportingStack);
    }
    return _BackgroundRefreshFailure(label, e, stackTrace);
  }
}

void _logBackgroundRefreshFailure(
  String message,
  _BackgroundRefreshFailure failure,
) {
  debugPrint('[BapU] $message (${failure.label}): ${failure.error}');
  debugPrintStack(stackTrace: failure.stackTrace);
}

class _BackgroundRefreshFailure {
  const _BackgroundRefreshFailure(this.label, this.error, this.stackTrace);

  final String label;
  final Object error;
  final StackTrace stackTrace;
}
