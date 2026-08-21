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
const kIosNotificationScheduleLeadTime = Duration(seconds: 30);

typedef ScheduledMealNotification = ({
  int id,
  DateTime fireInstant,
  String title,
  String body,
});

typedef IosMealWeek = ({DateTime startDate, WeekMeal weekMeal});
typedef IosMealWeekLoader = Future<IosMealWeek?> Function();
typedef IosAuthorizationStatusReader =
    Future<MealNotificationAuthorizationStatus> Function();
typedef IosPendingIdReader = Future<List<int>> Function();
typedef IosPendingCanceler = Future<void> Function(int id);
typedef IosNotificationUpserter =
    Future<void> Function(ScheduledMealNotification notification);

enum IosMealReconciliationOutcome {
  scheduled,
  notAuthorized,
  currentWeekUnavailable,
}

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
  required IosMealWeek currentWeek,
  IosMealWeek? nextWeek,
  Duration leadTime = kIosNotificationScheduleLeadTime,
  int maxNotifications = kMaxScheduledMealNotifications,
}) {
  if (!settings.enabled || maxNotifications <= 0) return const [];

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
    if (batch.length + slot.notifications.length > maxNotifications) break;
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

Future<IosMealReconciliationOutcome> reconcileIosMealNotifications({
  required NotificationSettings settings,
  bool clearPendingFirst = false,
  IosMealWeek? currentWeek,
  IosMealWeek? nextWeek,
  DateTime Function()? nowProvider,
  IosMealWeekLoader? loadCurrentWeek,
  IosMealWeekLoader? loadNextWeek,
  IosAuthorizationStatusReader? readAuthorizationStatus,
  IosPendingIdReader? readPendingIds,
  IosPendingCanceler? cancelPending,
  IosNotificationUpserter? upsertNotification,
  AppLocalizations? l10n,
}) async {
  final authorization =
      await (readAuthorizationStatus ?? mealNotificationAuthorizationStatus)();
  if (authorization == MealNotificationAuthorizationStatus.notAuthorized) {
    return IosMealReconciliationOutcome.notAuthorized;
  }

  final pendingReader = readPendingIds ?? pendingNotificationIds;
  final canceler = cancelPending ?? cancelPendingNotification;
  final pending = (await pendingReader())
      .where(isScheduledMealNotificationId)
      .toList(growable: false);
  if (clearPendingFirst) {
    for (final id in pending) {
      await canceler(id);
    }
  }

  final instant = (nowProvider ?? DateTime.now)();
  final current =
      currentWeek ??
      await (loadCurrentWeek ?? () => _loadCachedWeek(instant))();
  if (current == null) {
    return IosMealReconciliationOutcome.currentWeekUnavailable;
  }
  final next =
      nextWeek ?? await (loadNextWeek ?? () => _loadCachedNextWeek(instant))();

  final expectedNextWeekStart = current.startDate.add(const Duration(days: 7));
  final retainedIds = clearPendingFirst || next != null
      ? const <int>[]
      : pending
            .where((id) => _idTargetsWeek(id, expectedNextWeekStart))
            .toList(growable: false);
  final batch = buildMealNotificationBatch(
    settings: settings,
    l10n: l10n ?? notificationLocalizations(),
    now: instant,
    currentWeek: current,
    nextWeek: next,
    maxNotifications: kMaxScheduledMealNotifications - retainedIds.length,
  );
  final desiredIds = batch.map((notification) => notification.id).toSet();

  if (!clearPendingFirst) {
    for (final id in pending) {
      if (!retainedIds.contains(id) && !desiredIds.contains(id)) {
        await canceler(id);
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
          '[BapU] skipped elapsed iOS meal notification ${notification.id}',
        );
        continue;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
  return IosMealReconciliationOutcome.scheduled;
}

Future<void> cancelAllPendingMealNotifications({
  IosPendingIdReader? readPendingIds,
  IosPendingCanceler? cancelPending,
}) async {
  final ids = await (readPendingIds ?? pendingNotificationIds)();
  final canceler = cancelPending ?? cancelPendingNotification;
  for (final id in ids.where(isScheduledMealNotificationId)) {
    try {
      await canceler(id);
    } catch (error, stackTrace) {
      debugPrint('[BapU] failed to cancel iOS meal notification $id: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }
}

Future<IosMealWeek?> _loadCachedWeek(DateTime now) async {
  final startDate = kstWeekStartForInstant(now);
  final cached = await MealCache().readValidatedMealForWeek(startDate);
  return cached == null
      ? null
      : (startDate: startDate, weekMeal: cached.weekMeal);
}

Future<IosMealWeek?> _loadCachedNextWeek(DateTime now) async {
  final startDate = kstWeekStartForInstant(now).add(const Duration(days: 7));
  final cached = await MealCache(
    fileName: StorageKeys.nextMealCacheFile,
  ).readValidatedMealForWeek(startDate);
  return cached == null
      ? null
      : (startDate: startDate, weekMeal: cached.weekMeal);
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
