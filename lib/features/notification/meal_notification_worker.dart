import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/features/settings/notification/notification_settings_store.dart';
import 'package:meal_client/features/widget/widget_service.dart';
import 'ios_meal_notification_scheduler.dart';
import 'meal_notification_mutation_lock.dart';
import 'meal_notification_content_builder.dart';
import 'meal_notification_period.dart';
import 'notification_platform.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';

typedef BackgroundCacheRefresh = Future<void> Function();
typedef BackgroundNotificationReconcile = Future<void> Function();
typedef BackgroundNotificationSnapshot = ({
  NotificationSettings settings,
  int generation,
  String? currentRevision,
  String? nextRevision,
});
typedef BackgroundNotificationSnapshotLoader =
    Future<BackgroundNotificationSnapshot> Function();

/// 디버그 빌드에서 UI의 테스트 버튼이 호출하는 함수.
/// 백그라운드 태스크와 동일한 로직을 메인 isolate에서 즉시 실행한다.
/// [keywordsOverride]를 전달하면 SharedPreferences 값 대신 그 키워드 리스트로
/// 검사한다. (UI에서 막 입력한 값이 prefs에 아직 안 들어간 경우 활용)
Future<void> testMealKeywordCheck({
  List<String>? keywordsOverride,
  MealNotificationPeriod period = MealNotificationPeriod.lunch,
}) => _runMealKeywordCheck(
  period: period,
  targetDate: notificationTargetDateFor(period, DateTime.now()),
  keywordsOverride: keywordsOverride,
  checkDay: false, // 테스트는 요일 필터 무시하고 매칭 로직만 확인
);

/// Workmanager 백그라운드 격리체(isolate) 진입점.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    if (taskName == mealRefreshTaskName ||
        taskName == Workmanager.iOSBackgroundTask) {
      return refreshBackgroundMealAndInfoCaches();
    }

    final period = periodFromTaskName(taskName);
    if (period != null) {
      try {
        await handleKeywordNotificationTask(
          period: period,
          targetDateInput: inputData?['targetDate'],
        );
      } catch (e, stackTrace) {
        debugPrint('[BapU] keyword notification worker failed: $e');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }
    }
    return true;
  });
}

typedef MealKeywordCheckRunner =
    Future<void> Function(MealNotificationPeriod period, DateTime targetDate);
typedef KeywordNotificationRescheduler =
    Future<void> Function(MealNotificationPeriod period);

/// Workmanager 태스크의 저장된 메뉴 대상 날짜를 처리하고 다음 작업을 예약한다.
///
/// 이전 버전이 만든 태스크에는 대상 날짜가 없으므로 검사하지 않고 다음 작업만
/// 새 형식으로 예약한다. 지연 실행 시 실제 실행 시각으로 대상을 다시 계산하면
/// 일요일 밤 알림이 화요일 메뉴를 검사할 수 있기 때문이다.
Future<void> handleKeywordNotificationTask({
  required MealNotificationPeriod period,
  required Object? targetDateInput,
  MealKeywordCheckRunner? runCheck,
  KeywordNotificationRescheduler? reschedule,
}) async {
  final targetDate = notificationTargetDateFromString(targetDateInput);
  if (targetDate == null) {
    debugPrint('[BapU] legacy keyword notification task skipped');
  } else {
    await (runCheck ??
        (period, targetDate) => _runMealKeywordCheck(
          period: period,
          targetDate: targetDate,
        ))(period, targetDate);
  }
  await (reschedule ?? _rescheduleForNextDay)(period);
}

Future<bool> refreshBackgroundMealAndInfoCaches({
  BackgroundCacheRefresh? refreshMealCache,
  BackgroundCacheRefresh? refreshInfoCache,
  BackgroundCacheRefresh? refreshWidget,
  BackgroundNotificationReconcile? reconcileIosNotifications,
  MealNotificationPlatform? platform,
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
    _captureBackgroundRefreshFailure('meal', mealRefresh),
    _captureBackgroundRefreshFailure('info', infoRefresh),
  ]);

  final mealFailure = failures[0];
  if (mealFailure != null) {
    _logBackgroundRefreshFailure('background meal refresh failed', mealFailure);
    return false;
  }

  if ((platform ?? mealNotificationPlatform) == MealNotificationPlatform.ios) {
    final notificationFailure = await _captureBackgroundRefreshFailure(
      'notification',
      reconcileIosNotifications ?? _reconcileIosNotificationsFromCache,
    );
    if (notificationFailure != null) {
      _logBackgroundRefreshFailure(
        'background meal notification reconciliation failed',
        notificationFailure,
      );
      return false;
    }
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
  );
  if (widgetFailure != null) {
    _logBackgroundRefreshFailure(
      'background widget refresh failed',
      widgetFailure,
    );
    return false;
  }

  return true;
}

Future<void> _reconcileIosNotificationsFromCache() async {
  await initNotifications();
  await reconcileBackgroundIosMealNotifications();
}

Future<void> reconcileBackgroundIosMealNotifications({
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
          (settings) => reconcileIosMealNotifications(settings: settings))(
        snapshot.settings,
      );
    } else {
      await (cancelPending ?? cancelAllPendingMealNotifications)();
    }

    final after = await snapshotLoader();
    if (_sameBackgroundSnapshot(snapshot, after)) return;
    snapshot = after;
  }
  throw StateError('iOS notification inputs did not stabilize');
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
  final dormTypes = settings.dormMealTypes.map((item) => item.name).toList()
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
) async {
  try {
    await refresh();
    return null;
  } catch (e, stackTrace) {
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

Future<void> _rescheduleForNextDay(MealNotificationPeriod period) async {
  final prefs = await SharedPreferences.getInstance();
  final settings = loadNotificationSettings(prefs);
  if (!settings.enabled) return;
  final alertTime = settings.alertTimeOf(period);
  if (alertTime == null || settings.days.isEmpty) return;

  assert(() {
    debugPrint(
      '[BapU] worker: rescheduling ${period.name} for next day at '
      '${alertTime.hour}:${alertTime.minute}',
    );
    return true;
  }());
  await scheduleKeywordNotificationFor(period, alertTime, settings.days);
  assert(() {
    debugPrint('[BapU] worker: reschedule call completed');
    return true;
  }());
}

Future<void> _runMealKeywordCheck({
  required MealNotificationPeriod period,
  required DateTime targetDate,
  List<String>? keywordsOverride,
  bool checkDay = true,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final settings = loadNotificationSettings(prefs);
  if (!settings.enabled) return;

  final now = DateTime.now();
  if (isNotificationTargetInPast(targetDate, now)) return;
  final targetDay = DayOfWeek.values[targetDate.weekday - 1];

  if (checkDay && !settings.days.contains(targetDay)) return;

  final deliverySettings = normalizeNotificationDeliverySettings(
    settings,
    keywordsOverride: keywordsOverride,
  );
  if (deliverySettings.cafeterias.isEmpty) return;

  final WeekMeal weekMeal;
  try {
    weekMeal = await loadMealForNotificationTarget(
      targetDate: targetDate,
      now: now,
    );
  } catch (_) {
    return;
  }

  final contents = buildMealNotificationContents(
    weekMeal: weekMeal,
    targetDate: targetDate,
    period: period,
    settings: deliverySettings,
    l10n: notificationLocalizations(),
  );
  if (contents.isEmpty) return;

  await initNotifications();
  for (final content in contents) {
    await showMealNotification(
      id: content.id,
      title: content.title,
      body: content.body,
    );
  }
}

/// [targetDate]가 현재 KST 날짜보다 이전인지 반환한다.
bool isNotificationTargetInPast(DateTime targetDate, DateTime now) {
  return targetDate.isBefore(kstCalendarDate(now));
}

typedef CurrentWeekMealLoader = Future<WeekMeal> Function();
typedef DatedWeekMealLoader = Future<WeekMeal> Function(String weekStart);

/// 대상 날짜가 현재 주면 기존 캐시 경로를, 아니면 날짜 지정 API를 사용한다.
///
/// 날짜 지정 API 결과는 현재 주 캐시에 쓰지 않아 일요일의 다음 주 조회가
/// `meal.json`을 덮어쓰지 않는다.
Future<WeekMeal> loadMealForNotificationTarget({
  required DateTime targetDate,
  required DateTime now,
  CurrentWeekMealLoader? loadCurrentWeek,
  DatedWeekMealLoader? loadDatedWeek,
}) {
  final targetWeekStart = kstWeekStartFromDate(targetDate);
  final currentWeekStart = kstWeekStartFromDate(kstCalendarDate(now));
  if (targetWeekStart == currentWeekStart) {
    return (loadCurrentWeek ??
        () => MealRefreshService().getFreshOrRefreshMealData())();
  }

  return (loadDatedWeek ?? fetchMealDataForWeek)(
    notificationTargetDateString(targetWeekStart),
  );
}
