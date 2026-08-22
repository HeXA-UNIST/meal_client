import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'meal_notification_content_builder.dart';
import 'meal_notification_period.dart';
import 'meal_notification_time.dart';
import 'notification_service.dart';

const kScheduledMealNotificationIdStart = 100000000;
const kScheduledMealNotificationIdEnd = 140000000;
const kMaxScheduledMealNotifications = 64;
const kMealNotificationScheduleLeadTime = Duration(seconds: 30);

/// 예약 시각이 지난 pending을 stale로 판정하기까지 기다리는 시간.
///
/// Android는 `inexactAllowWhileIdle` 알람에 지연 창을 붙여 예약 시각보다 늦게
/// 배달한다(AlarmManager는 잔여 시간의 75%를 창으로 잡고 1시간에서 자른다).
/// 창이 닫히기 전에 reconcile이 돌면 아직 배달되지 않은 알림이 batch에서 빠지는데,
/// 이때 곧바로 취소하면 사용자는 그 끼니 알림을 영영 받지 못한다. 그래서 시각이
/// 지난 pending도 이 시간 동안은 배달 대기로 보고 그대로 둔다.
const kMealNotificationDeliveryGrace = Duration(hours: 1);

typedef ScheduledMealNotification = ({
  int id,
  DateTime fireInstant,
  String title,
  String body,
});

typedef ScheduledMealWeek = ({DateTime startDate, WeekMeal weekMeal});
typedef ScheduledMealWeekLoader = Future<ScheduledMealWeek?> Function();
typedef MealNotificationAuthorizationStatusReader =
    Future<MealNotificationAuthorizationStatus> Function();
typedef ScheduledMealPendingIdReader = Future<List<int>> Function();
typedef ScheduledMealPendingCanceler = Future<void> Function(int id);
typedef ScheduledMealNotificationUpserter =
    Future<void> Function(ScheduledMealNotification notification);

bool isScheduledMealNotificationId(int id) =>
    id >= kScheduledMealNotificationIdStart &&
    id < kScheduledMealNotificationIdEnd;

int scheduledMealNotificationId({
  required MealNotificationPeriod period,
  required int contentId,
  required DateTime targetDate,
}) {
  final groupCode = switch (contentId) {
    >= 1 && <= 4 => contentId - 1,
    9 => 9,
    _ => throw ArgumentError.value(contentId, 'contentId'),
  };
  final date = DateTime.utc(targetDate.year, targetDate.month, targetDate.day);
  final daysSinceEpoch = date.difference(DateTime.utc(1970)).inDays;
  final id =
      kScheduledMealNotificationIdStart +
      period.index * 10000000 +
      groupCode * 1000000 +
      daysSinceEpoch;
  if (!isScheduledMealNotificationId(id)) {
    throw StateError('예약 알림 ID가 소유 범위를 벗어났습니다: $id');
  }
  return id;
}

List<ScheduledMealNotification> buildMealNotificationBatch({
  required NotificationSettings settings,
  required AppLocalizations l10n,
  required DateTime now,
  required ScheduledMealWeek currentWeek,
  ScheduledMealWeek? nextWeek,
  Duration leadTime = kMealNotificationScheduleLeadTime,
  int maxNotifications = kMaxScheduledMealNotifications,
}) {
  if (!settings.enabled || maxNotifications <= 0) {
    return const [];
  }

  final deliverySettings = normalizeNotificationDeliverySettings(settings);
  final slots = <_NotificationSlot>[];
  for (final week in [currentWeek, ?nextWeek]) {
    for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
      final targetDate = week.startDate.add(Duration(days: dayOffset));
      final targetDay = DayOfWeek.values[targetDate.weekday - 1];
      if (!settings.days.contains(targetDay)) continue;

      for (final period in MealNotificationPeriod.values) {
        final alertTime = settings.alertTimeOf(period);
        if (alertTime == null) continue;
        final fireInstant = fireInstantForTarget(
          period: period,
          targetKstDate: targetDate,
          alertTime: alertTime,
        );
        if (fireInstant.isBefore(now.add(leadTime))) continue;

        final contents = buildMealNotificationContents(
          weekMeal: week.weekMeal,
          targetDate: targetDate,
          period: period,
          settings: deliverySettings,
          l10n: l10n,
        );
        if (contents.isEmpty) continue;
        slots.add(
          _NotificationSlot(
            fireInstant: fireInstant,
            notifications: [
              for (final content in contents)
                (
                  id: scheduledMealNotificationId(
                    period: period,
                    contentId: content.id,
                    targetDate: targetDate,
                  ),
                  fireInstant: fireInstant,
                  title: content.title,
                  body: content.body,
                ),
            ],
          ),
        );
      }
    }
  }

  slots.sort((first, second) {
    final byTime = first.fireInstant.compareTo(second.fireInstant);
    if (byTime != 0) return byTime;
    return first.notifications.first.id.compareTo(
      second.notifications.first.id,
    );
  });
  final batch = <ScheduledMealNotification>[];
  for (final slot in slots) {
    if (batch.length + slot.notifications.length > maxNotifications) {
      break;
    }
    batch.addAll(slot.notifications);
  }
  return List.unmodifiable(batch);
}

class _NotificationSlot {
  const _NotificationSlot({
    required this.fireInstant,
    required this.notifications,
  });

  final DateTime fireInstant;
  final List<ScheduledMealNotification> notifications;
}

Future<void> reconcileScheduledMealNotifications({
  required NotificationSettings settings,
  bool Function()? isCurrent,
  ScheduledMealWeek? currentWeek,
  ScheduledMealWeek? nextWeek,
  DateTime Function()? nowProvider,
  ScheduledMealWeekLoader? loadCurrentWeek,
  ScheduledMealWeekLoader? loadNextWeek,
  MealNotificationAuthorizationStatusReader? readAuthorizationStatus,
  ScheduledMealPendingIdReader? readPendingIds,
  ScheduledMealPendingCanceler? cancelPending,
  ScheduledMealNotificationUpserter? upsertNotification,
  int maxNotifications = kMaxScheduledMealNotifications,
  Duration deliveryGrace = kMealNotificationDeliveryGrace,
  AppLocalizations? l10n,
}) async {
  final currentGeneration = isCurrent ?? () => true;
  final authorization =
      await (readAuthorizationStatus ?? mealNotificationAuthorizationStatus)();
  if (!currentGeneration()) {
    return;
  }
  if (authorization == MealNotificationAuthorizationStatus.notAuthorized) {
    return;
  }

  final pendingReader = readPendingIds ?? pendingMealNotificationIds;
  final canceler = cancelPending ?? cancelPendingMealNotification;
  final pending = (await pendingReader())
      .where(isScheduledMealNotificationId)
      .toList(growable: false);
  if (!currentGeneration()) {
    return;
  }
  final instant = (nowProvider ?? DateTime.now)();
  final current =
      currentWeek ??
      await (loadCurrentWeek ?? () => _loadCachedWeek(instant))();
  if (!currentGeneration()) {
    return;
  }
  if (current == null) {
    return;
  }
  final next =
      nextWeek ?? await (loadNextWeek ?? () => _loadCachedNextWeek(instant))();
  if (!currentGeneration()) {
    return;
  }

  final expectedNextWeekStart = current.startDate.add(const Duration(days: 7));
  final retainedIds = <int>{
    if (next == null)
      ...pending.where((id) => _idTargetsWeek(id, expectedNextWeekStart)),
    // 배달 창이 아직 열려 있는 pending은 batch에서 빠지더라도 취소하지 않는다.
    ...pending.where(
      (id) => _isAwaitingDelivery(
        id: id,
        settings: settings,
        now: instant,
        grace: deliveryGrace,
      ),
    ),
  };
  final batch = buildMealNotificationBatch(
    settings: settings,
    l10n: l10n ?? notificationLocalizations(),
    now: instant,
    currentWeek: current,
    nextWeek: next,
    maxNotifications: maxNotifications - retainedIds.length,
  );
  final desiredIds = batch.map((notification) => notification.id).toSet();

  Object? firstError;
  StackTrace? firstStackTrace;
  for (final id in pending) {
    if (!retainedIds.contains(id) && !desiredIds.contains(id)) {
      if (!currentGeneration()) {
        return;
      }
      try {
        await canceler(id);
      } catch (error, stackTrace) {
        debugPrint('[BapU] failed to cancel meal notification $id: $error');
        debugPrintStack(stackTrace: stackTrace);
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
  }

  final upsert =
      upsertNotification ??
      (notification) => scheduleMealNotification(
        id: notification.id,
        fireInstant: notification.fireInstant,
        title: notification.title,
        body: notification.body,
      );
  for (final notification in batch) {
    if (!currentGeneration()) {
      return;
    }
    if (notification.fireInstant.isBefore((nowProvider ?? DateTime.now)())) {
      continue;
    }
    try {
      await upsert(notification);
    } on ArgumentError catch (error, stackTrace) {
      final nowAfterFailure = (nowProvider ?? DateTime.now)();
      if (error.name == 'scheduledDate' &&
          notification.fireInstant.isBefore(nowAfterFailure)) {
        debugPrint(
          '[BapU] skipped elapsed meal notification ${notification.id}',
        );
        continue;
      }
      debugPrint(
        '[BapU] failed to schedule meal notification '
        '${notification.id}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    } catch (error, stackTrace) {
      debugPrint(
        '[BapU] failed to schedule meal notification '
        '${notification.id}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace!);
  }
}

Future<void> cancelAllPendingMealNotifications({
  ScheduledMealPendingIdReader? readPendingIds,
  ScheduledMealPendingCanceler? cancelPending,
}) async {
  final ids = await (readPendingIds ?? pendingMealNotificationIds)();
  final canceler = cancelPending ?? cancelPendingMealNotification;
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final id in ids.where(isScheduledMealNotificationId)) {
    try {
      await canceler(id);
    } catch (error, stackTrace) {
      debugPrint('[BapU] failed to cancel meal notification $id: $error');
      debugPrintStack(stackTrace: stackTrace);
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace!);
  }
}

Future<ScheduledMealWeek?> _loadCachedWeek(DateTime now) async {
  final startDate = kstWeekStartForInstant(now);
  final cached = await MealCache().readValidatedMealForWeek(startDate);
  return cached == null
      ? null
      : (startDate: startDate, weekMeal: cached.weekMeal);
}

Future<ScheduledMealWeek?> _loadCachedNextWeek(DateTime now) async {
  final startDate = kstWeekStartForInstant(now).add(const Duration(days: 7));
  final cached = await MealCache(
    fileName: StorageKeys.nextMealCacheFile,
  ).readValidatedMealForWeek(startDate);
  return cached == null
      ? null
      : (startDate: startDate, weekMeal: cached.weekMeal);
}

typedef _OwnedNotificationTarget = ({
  MealNotificationPeriod period,
  DateTime targetDate,
});

/// 소유 ID를 발급 근거였던 시간대와 KST 대상 날짜로 되돌린다.
_OwnedNotificationTarget? _ownedNotificationTarget(int id) {
  if (!isScheduledMealNotificationId(id)) return null;
  final periodIndex = (id - kScheduledMealNotificationIdStart) ~/ 10000000;
  if (periodIndex >= MealNotificationPeriod.values.length) return null;
  return (
    period: MealNotificationPeriod.values[periodIndex],
    targetDate: DateTime.utc(1970).add(Duration(days: id % 1000000)),
  );
}

/// 예약 시각은 지났지만 OS가 아직 배달하지 않았을 수 있는 pending인지 판단한다.
///
/// 현재 설정 기준으로 더 이상 발송 대상이 아닌 ID(시간대를 껐거나 요일을 뺀 경우)는
/// 사용자가 명시적으로 끈 것이므로 유예 없이 취소되게 둔다.
bool _isAwaitingDelivery({
  required int id,
  required NotificationSettings settings,
  required DateTime now,
  required Duration grace,
  Duration leadTime = kMealNotificationScheduleLeadTime,
}) {
  if (!settings.enabled) return false;

  final target = _ownedNotificationTarget(id);
  if (target == null) return false;

  final alertTime = settings.alertTimeOf(target.period);
  if (alertTime == null) return false;
  if (!settings.days.contains(
    DayOfWeek.values[target.targetDate.weekday - 1],
  )) {
    return false;
  }

  final DateTime fireInstant;
  try {
    fireInstant = fireInstantForTarget(
      period: target.period,
      targetKstDate: target.targetDate,
      alertTime: alertTime,
    );
  } on StateError {
    return false;
  }

  // batch는 `now + leadTime` 이후만 담으므로, 그 앞의 유예 구간만 여기서 맡는다.
  return !fireInstant.isBefore(now.subtract(grace)) &&
      fireInstant.isBefore(now.add(leadTime));
}

bool _idTargetsWeek(int id, DateTime weekStart) {
  final day = id % 1000000;
  final start = DateTime.utc(
    weekStart.year,
    weekStart.month,
    weekStart.day,
  ).difference(DateTime.utc(1970)).inDays;
  return day >= start && day < start + 7;
}
