import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/domain/meal.dart';
import 'meal_alert_period.dart';

const kMealKeywordTaskPrefix = 'meal_keyword_check_';

/// (예: `meal_keyword_check_morning`).
String taskNameOf(MealAlertPeriod period) =>
    '$kMealKeywordTaskPrefix${period.name}';

/// 태스크 이름에서 시간대를 파싱한다. 접두사 매칭 실패 시 null.
MealAlertPeriod? periodFromTaskName(String taskName) {
  if (!taskName.startsWith(kMealKeywordTaskPrefix)) return null;
  return MealAlertPeriod.tryFromName(
    taskName.substring(kMealKeywordTaskPrefix.length),
  );
}

/// [enabledDays]의 메뉴 요일에 해당하는 가장 가까운 실행 시각을 반환한다.
///
/// Workmanager의 실행 시각은 기기 현지 시간이지만, 메뉴와 워커의 요일 판정은
/// KST를 사용한다. 따라서 후보 시각에서 메뉴 대상 날짜를 구해 요일을 비교한다.
/// 선택된 요일이 없으면 알림을 예약하지 않는다.
DateTime? nextEnabledFireTime({
  required MealAlertPeriod period,
  required TimeOfDay alertTime,
  required Set<DayOfWeek> enabledDays,
  required DateTime now,
}) {
  if (enabledDays.isEmpty) return null;

  var candidate = DateTime(
    now.year,
    now.month,
    now.day,
    alertTime.hour,
    alertTime.minute,
  );
  if (!candidate.isAfter(now)) {
    candidate = DateTime(
      now.year,
      now.month,
      now.day + 1,
      alertTime.hour,
      alertTime.minute,
    );
  }

  for (var offset = 0; offset < 7; offset++) {
    final targetDate = notificationTargetDateFor(period, candidate);
    final targetDay = DayOfWeek.values[targetDate.weekday - 1];
    if (enabledDays.contains(targetDay)) return candidate;

    candidate = DateTime(
      candidate.year,
      candidate.month,
      candidate.day + 1,
      alertTime.hour,
      alertTime.minute,
    );
  }

  throw StateError('활성화된 알림 요일의 다음 실행 시각을 찾지 못했습니다.');
}

typedef KeywordNotificationScheduler =
    Future<void> Function(
      Map<MealAlertPeriod, TimeOfDay?> alertTimes,
      Set<DayOfWeek> enabledDays,
    );

typedef KeywordNotificationCanceler = Future<void> Function();

typedef KeywordTaskCanceler = Future<void> Function(String uniqueName);
typedef KeywordTaskRegistrar =
    Future<void> Function({
      required String uniqueName,
      required String taskName,
      required Duration initialDelay,
      required Map<String, dynamic> inputData,
    });

/// 예약 요청의 최종 처리 결과.
enum NotificationScheduleOutcome { scheduled, superseded, canceled, disposed }

/// 연속된 알림 설정 변경을 합치고, Workmanager 갱신을 순서대로 실행한다.
///
/// 설정 UI는 즉시 반영하되, 짧은 시간에 여러 번 누른 경우에는 마지막 상태만
/// 예약한다. 진행 중인 예약 뒤에 다음 작업을 연결하므로 이전 상태가 최종
/// Workmanager 등록을 덮어쓰지 않는다.
class NotificationScheduleCoordinator {
  NotificationScheduleCoordinator({
    KeywordNotificationScheduler? schedule,
    KeywordNotificationCanceler? cancel,
    this.debounce = const Duration(milliseconds: 300),
  }) : _schedule = schedule ?? scheduleAllKeywordNotifications,
       _cancel = cancel ?? cancelAllKeywordNotifications;

  final KeywordNotificationScheduler _schedule;
  final KeywordNotificationCanceler _cancel;
  final Duration debounce;

  Future<void> _queue = Future.value();
  Timer? _pendingTimer;
  Completer<NotificationScheduleOutcome>? _pendingCompleter;
  int _revision = 0;
  bool _disposed = false;

  /// 최신 [alertTimes], [enabledDays]로 예약을 요청한다.
  Future<NotificationScheduleOutcome> schedule(
    Map<MealAlertPeriod, TimeOfDay?> alertTimes,
    Set<DayOfWeek> enabledDays,
  ) {
    if (_disposed) return Future.value(NotificationScheduleOutcome.disposed);

    final snapshotTimes = Map<MealAlertPeriod, TimeOfDay?>.unmodifiable(
      alertTimes,
    );
    final snapshotDays = Set<DayOfWeek>.unmodifiable(enabledDays);
    _invalidatePending(NotificationScheduleOutcome.superseded);
    final revision = _revision;

    final completer = Completer<NotificationScheduleOutcome>();
    _pendingCompleter = completer;
    _pendingTimer = Timer(debounce, () {
      _pendingTimer = null;
      _pendingCompleter = null;
      _enqueueSchedule(revision, snapshotTimes, snapshotDays).then(
        completer.complete,
        onError: (Object error, StackTrace stackTrace) {
          completer.completeError(error, stackTrace);
        },
      );
    });
    return completer.future;
  }

  /// 디바운스를 거치지 않고 즉시 예약 작업을 큐에 추가한다.
  Future<NotificationScheduleOutcome> scheduleNow(
    Map<MealAlertPeriod, TimeOfDay?> alertTimes,
    Set<DayOfWeek> enabledDays,
  ) {
    if (_disposed) return Future.value(NotificationScheduleOutcome.disposed);

    final snapshotTimes = Map<MealAlertPeriod, TimeOfDay?>.unmodifiable(
      alertTimes,
    );
    final snapshotDays = Set<DayOfWeek>.unmodifiable(enabledDays);
    _invalidatePending(NotificationScheduleOutcome.superseded);
    return _enqueueSchedule(_revision, snapshotTimes, snapshotDays);
  }

  /// 보류 중인 예약 요청을 무효화하고, 모든 알림 작업을 취소한다.
  Future<void> cancelAll() {
    if (_disposed) return Future.value();

    _invalidatePending(NotificationScheduleOutcome.canceled);
    return _enqueue(_cancel);
  }

  /// 보류 중인 예약을 취소하고, 아직 시작하지 않은 예약 요청을 무효화한다.
  /// 이미 시작된 Workmanager 플러그인 호출은 중단할 수 없어 완료될 수 있다.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _invalidatePending(NotificationScheduleOutcome.disposed);
  }

  void _invalidatePending(NotificationScheduleOutcome outcome) {
    _revision++;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingCompleter?.complete(outcome);
    _pendingCompleter = null;
  }

  Future<NotificationScheduleOutcome> _enqueueSchedule(
    int revision,
    Map<MealAlertPeriod, TimeOfDay?> alertTimes,
    Set<DayOfWeek> enabledDays,
  ) => _enqueue(() async {
    if (_disposed) return NotificationScheduleOutcome.disposed;
    if (revision != _revision) {
      return NotificationScheduleOutcome.superseded;
    }
    await _schedule(alertTimes, enabledDays);
    return NotificationScheduleOutcome.scheduled;
  });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final queued = _queue.then<T>((_) => operation());
    // 예약 실패가 이후 요청을 막지 않게 큐는 항상 계속 진행한다.
    _queue = queued.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return queued;
  }
}

/// 지정한 [period]의 다음 알림을 [alertTime]에 실행되도록 등록한다.
/// 워커가 실행을 마치면 워커 자신이 다음 활성 메뉴 요일로 태스크를 재등록한다.
Future<void> scheduleKeywordNotificationFor(
  MealAlertPeriod period,
  TimeOfDay alertTime,
  Set<DayOfWeek> enabledDays, {
  DateTime Function()? nowProvider,
  KeywordTaskCanceler? cancelTask,
  KeywordTaskRegistrar? registerTask,
}) async {
  final taskName = taskNameOf(period);
  try {
    await (cancelTask ?? Workmanager().cancelByUniqueName)(taskName);

    final now = (nowProvider ?? DateTime.now)();
    final next = nextEnabledFireTime(
      period: period,
      alertTime: alertTime,
      enabledDays: enabledDays,
      now: now,
    );
    if (next == null) return;
    final delay = next.difference(now);
    final targetDate = notificationTargetDateFor(period, next);

    assert(() {
      debugPrint(
        '[BapU] ${period.name} scheduled at $next '
        '(in ${delay.inMinutes}m ${delay.inSeconds % 60}s)',
      );
      return true;
    }());

    await (registerTask ?? _registerKeywordTask)(
      uniqueName: taskName,
      taskName: taskName,
      initialDelay: delay,
      inputData: {'targetDate': notificationTargetDateString(targetDate)},
    );
  } catch (e, st) {
    assert(() {
      debugPrint('[BapU] schedule failed for ${period.name}: $e\n$st');
      return true;
    }());
  }
}

Future<void> _registerKeywordTask({
  required String uniqueName,
  required String taskName,
  required Duration initialDelay,
  required Map<String, dynamic> inputData,
}) {
  return Workmanager().registerOneOffTask(
    uniqueName,
    taskName,
    initialDelay: initialDelay,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    inputData: inputData,
  );
}

Future<void> cancelKeywordNotificationFor(MealAlertPeriod period) async {
  try {
    await Workmanager().cancelByUniqueName(taskNameOf(period));
  } catch (e, st) {
    assert(() {
      debugPrint('[BapU] cancel failed for ${period.name}: $e\n$st');
      return true;
    }());
  }
}

/// [alertTimes]에 시각이 설정된 시간대는 등록하고, 없는 시간대는 취소한다.
Future<void> scheduleAllKeywordNotifications(
  Map<MealAlertPeriod, TimeOfDay?> alertTimes,
  Set<DayOfWeek> enabledDays,
) async {
  for (final period in MealAlertPeriod.values) {
    final time = alertTimes[period];
    if (time == null) {
      await cancelKeywordNotificationFor(period);
    } else {
      await scheduleKeywordNotificationFor(period, time, enabledDays);
    }
  }
}

/// 모든 시간대 태스크를 취소한다.
Future<void> cancelAllKeywordNotifications() async {
  for (final period in MealAlertPeriod.values) {
    await cancelKeywordNotificationFor(period);
  }
}
