import 'dart:async';

import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'meal_notification_mutation_lock.dart';
import 'notification_platform.dart';
import 'notification_service.dart';
import 'scheduled_meal_notifications.dart';

export 'meal_notification_time.dart'
    show fireInstantForTarget, LocalDateTimeFactory;

typedef MealNotificationScheduler =
    Future<void> Function(
      NotificationSettings settings, {
      required bool Function() isCurrent,
    });

typedef MealNotificationCanceler = Future<void> Function();

/// 예약 요청의 최종 처리 결과.
enum NotificationScheduleOutcome { scheduled, superseded, canceled, disposed }

/// 연속된 알림 설정 변경을 합치고, 플랫폼 예약 갱신을 순서대로 실행한다.
///
/// 설정 UI는 즉시 반영하되, 짧은 시간에 여러 번 누른 경우에는 마지막 상태만
/// 예약한다. 진행 중인 예약 뒤에 다음 작업을 연결하므로 이전 상태가 최종
/// 플랫폼 등록을 덮어쓰지 않는다.
class NotificationScheduleCoordinator {
  NotificationScheduleCoordinator({
    MealNotificationScheduler? schedule,
    MealNotificationCanceler? cancel,
    this.debounce = const Duration(milliseconds: 300),
  }) : _schedule = schedule ?? scheduleMealNotifications,
       _cancel = cancel ?? cancelAllMealNotifications;

  final MealNotificationScheduler _schedule;
  final MealNotificationCanceler _cancel;
  final Duration debounce;

  Future<void> _queue = Future.value();
  Timer? _pendingTimer;
  Completer<NotificationScheduleOutcome>? _pendingCompleter;
  int _revision = 0;
  bool _disposed = false;

  /// 최신 [settings] 스냅샷으로 예약을 요청한다.
  Future<NotificationScheduleOutcome> schedule(NotificationSettings settings) {
    if (_disposed) return Future.value(NotificationScheduleOutcome.disposed);

    final snapshot = settings;
    _invalidatePending(NotificationScheduleOutcome.superseded);
    final revision = _revision;

    final completer = Completer<NotificationScheduleOutcome>();
    _pendingCompleter = completer;
    _pendingTimer = Timer(debounce, () {
      _pendingTimer = null;
      _pendingCompleter = null;
      _enqueueSchedule(revision, snapshot).then(
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
    NotificationSettings settings,
  ) {
    if (_disposed) return Future.value(NotificationScheduleOutcome.disposed);

    final snapshot = settings;
    _invalidatePending(NotificationScheduleOutcome.superseded);
    return _enqueueSchedule(_revision, snapshot);
  }

  /// 보류 중인 예약 요청을 무효화하고, 모든 알림 작업을 취소한다.
  Future<void> cancelAll() {
    if (_disposed) return Future.value();

    _invalidatePending(NotificationScheduleOutcome.canceled);
    return _enqueue(_cancel);
  }

  /// 보류 중인 예약을 취소하고, 아직 시작하지 않은 예약 요청을 무효화한다.
  /// 이미 시작된 플러그인 호출은 중단할 수 없어 완료될 수 있다.
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
    NotificationSettings settings,
  ) => _enqueue(() async {
    if (_disposed) return NotificationScheduleOutcome.disposed;
    if (revision != _revision) {
      return NotificationScheduleOutcome.superseded;
    }
    await _schedule(
      settings,
      isCurrent: () => !_disposed && revision == _revision,
    );
    return revision == _revision
        ? NotificationScheduleOutcome.scheduled
        : NotificationScheduleOutcome.superseded;
  });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final queued = _queue.then<T>((_) => operation());
    // 예약 실패가 이후 요청을 막지 않게 큐는 항상 계속 진행한다.
    _queue = queued.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return queued;
  }
}

/// Android와 iOS 모두 OS에 one-shot 알림을 미리 예약한다.
Future<void> scheduleMealNotifications(
  NotificationSettings settings, {
  bool Function()? isCurrent,
  MealNotificationPlatform? platform,
  MealNotificationScheduler? iosScheduler,
  MealNotificationScheduler? androidScheduler,
}) async {
  switch (platform ?? mealNotificationPlatform) {
    case MealNotificationPlatform.ios:
      await (iosScheduler ?? _scheduleIosMealNotifications)(
        settings,
        isCurrent: isCurrent ?? () => true,
      );
      return;
    case MealNotificationPlatform.android:
      await (androidScheduler ?? _scheduleAndroidMealNotifications)(
        settings,
        isCurrent: isCurrent ?? () => true,
      );
      return;
    case MealNotificationPlatform.unsupported:
      return;
  }
}

Future<void> _scheduleIosMealNotifications(
  NotificationSettings settings, {
  required bool Function() isCurrent,
}) async {
  await _scheduleNativeMealNotifications(
    settings,
    platform: MealNotificationPlatform.ios,
    maxNotifications: kMaxScheduledMealNotifications,
    isCurrent: isCurrent,
  );
}

Future<void> _scheduleAndroidMealNotifications(
  NotificationSettings settings, {
  required bool Function() isCurrent,
}) => _scheduleNativeMealNotifications(
  settings,
  platform: MealNotificationPlatform.android,
  maxNotifications: null,
  isCurrent: isCurrent,
);

Future<void> _scheduleNativeMealNotifications(
  NotificationSettings settings, {
  required MealNotificationPlatform platform,
  required int? maxNotifications,
  required bool Function() isCurrent,
}) => withMealNotificationMutationLock(
  () => reconcileScheduledMealNotifications(
    settings: settings,
    isCurrent: isCurrent,
    maxNotifications: maxNotifications,
    readAuthorizationStatus: () =>
        mealNotificationAuthorizationStatus(platform: platform),
    readPendingIds: () => pendingMealNotificationIds(platform: platform),
    cancelPending: (id) =>
        cancelPendingMealNotification(id, platform: platform),
    upsertNotification: (notification) => scheduleMealNotification(
      id: notification.id,
      fireInstant: notification.fireInstant,
      title: notification.title,
      body: notification.body,
      platform: platform,
    ),
  ),
);

Future<void> cancelAllMealNotifications({
  MealNotificationPlatform? platform,
  MealNotificationCanceler? iosCancel,
  MealNotificationCanceler? androidCancel,
  MealNotificationMutationSection? mutationSection,
}) => switch (platform ?? mealNotificationPlatform) {
  MealNotificationPlatform.ios =>
    (mutationSection ?? withMealNotificationMutationLock)(
      iosCancel ??
          () => cancelAllPendingMealNotifications(
            readPendingIds: iosPendingNotificationIds,
            cancelPending: cancelIosPendingNotification,
          ),
    ),
  MealNotificationPlatform.android =>
    (mutationSection ?? withMealNotificationMutationLock)(
      androidCancel ??
          () => cancelAllPendingMealNotifications(
            readPendingIds: androidPendingNotificationIds,
            cancelPending: cancelAndroidPendingNotification,
          ),
    ),
  MealNotificationPlatform.unsupported => Future.value(),
};
