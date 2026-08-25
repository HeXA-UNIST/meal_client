import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack;
import 'package:flutter/material.dart' show TimeOfDay;

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
const _notificationPeriodStride = 10000000;
const _notificationGroupStride = 1000000;
const _notificationSlotStride = 100000;
const _notificationDateModulo = 100000;

/// 예약 시각이 지난 pending을 stale로 판정하기까지 기다리는 시간.
///
/// Android는 `inexactAllowWhileIdle` 알람을 예약 시각이 아니라 지연 창 안에서
/// 배달한다. 창이 닫히기 전에 reconcile이 돌면 아직 배달되지 않은 알림이 batch에서
/// 빠지는데, 이때 곧바로 취소하면 사용자는 그 끼니 알림을 영영 받지 못한다.
/// 그래서 시각이 지난 pending도 이 시간 동안은 배달 대기로 보고 그대로 둔다.
///
/// 1시간은 Android 12+ 문서가 말하는 통상 창 상한에 맞춘 값이다. Doze나 절전
/// 모드에서는 그보다 더 밀릴 수 있으므로 절대 보장이 아니다 — 그 경우 유예가
/// 끝난 뒤의 reconcile이 아직 pending인 알림을 취소할 수 있다.
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
  required TimeOfDay alertTime,
}) {
  final groupCode = switch (contentId) {
    >= 1 && <= 4 => contentId - 1,
    9 => 9,
    _ => throw ArgumentError.value(contentId, 'contentId'),
  };
  final slotIndex = period.allSlots.indexWhere(
    (slot) => slot.hour == alertTime.hour && slot.minute == alertTime.minute,
  );
  if (slotIndex < 0) {
    throw ArgumentError.value(alertTime, 'alertTime');
  }
  final date = DateTime.utc(targetDate.year, targetDate.month, targetDate.day);
  final daysSinceEpoch = date.difference(DateTime.utc(1970)).inDays;
  if (daysSinceEpoch < 0 || daysSinceEpoch >= _notificationDateModulo) {
    throw ArgumentError.value(targetDate, 'targetDate');
  }
  final id =
      kScheduledMealNotificationIdStart +
      period.index * _notificationPeriodStride +
      groupCode * _notificationGroupStride +
      slotIndex * _notificationSlotStride +
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
                    alertTime: alertTime,
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

  final localizations = l10n ?? notificationLocalizations();
  final expectedNextWeekStart = current.startDate.add(const Duration(days: 7));
  final retainedIds = <int>{
    if (next == null)
      ...pending.where(
        (id) =>
            _idTargetsWeek(id, expectedNextWeekStart) &&
            _matchesCurrentNotificationSettings(id, settings),
      ),
    // 배달 창이 아직 열려 있는 pending은 batch에서 빠지더라도 취소하지 않는다.
    ...pending.where(
      _awaitingDeliveryIds(
        settings: settings,
        l10n: localizations,
        now: instant,
        currentWeek: current,
        nextWeek: next,
        grace: deliveryGrace,
        maxNotifications: maxNotifications,
      ).contains,
    ),
  };
  final batch = buildMealNotificationBatch(
    settings: settings,
    l10n: localizations,
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

/// 예약 시각은 지났지만 OS가 아직 배달하지 않았을 수 있는 알림의 ID 집합.
///
/// [buildMealNotificationBatch]를 유예 구간에 대해 한 번 더 돌려서 구한다. 그래야
/// 알림 on/off, 시간대, 요일뿐 아니라 대상 식당·기숙사 메뉴 종류·키워드·해당 끼니
/// 메뉴 존재 여부까지 본 batch와 똑같은 기준으로 판정된다. 사용자가 방금 끈 대상은
/// 여기서 빠지므로 유예 없이 취소된다.
///
/// 본 batch는 `now + leadTime` 이후만 담으므로 두 구간은 겹치거나 벌어지지 않는다.
Set<int> _awaitingDeliveryIds({
  required NotificationSettings settings,
  required AppLocalizations l10n,
  required DateTime now,
  required ScheduledMealWeek currentWeek,
  required ScheduledMealWeek? nextWeek,
  required Duration grace,
  required int maxNotifications,
  Duration leadTime = kMealNotificationScheduleLeadTime,
}) {
  final deadline = now.add(leadTime);
  return buildMealNotificationBatch(
        settings: settings,
        l10n: l10n,
        now: now.subtract(grace),
        currentWeek: currentWeek,
        nextWeek: nextWeek,
        leadTime: Duration.zero,
        maxNotifications: maxNotifications,
      )
      .where((notification) => notification.fireInstant.isBefore(deadline))
      .map((notification) => notification.id)
      .toSet();
}

typedef _OwnedNotificationTarget = ({
  MealNotificationPeriod period,
  int groupCode,
  DateTime targetDate,
  TimeOfDay alertTime,
});

_OwnedNotificationTarget? _ownedNotificationTarget(int id) {
  if (!isScheduledMealNotificationId(id)) return null;

  final relativeId = id - kScheduledMealNotificationIdStart;
  final periodIndex = relativeId ~/ _notificationPeriodStride;
  if (periodIndex >= MealNotificationPeriod.values.length) return null;
  final period = MealNotificationPeriod.values[periodIndex];
  final withinPeriod = relativeId % _notificationPeriodStride;
  final groupCode = withinPeriod ~/ _notificationGroupStride;
  if (groupCode != 9 && (groupCode < 0 || groupCode > 3)) return null;
  final withinGroup = withinPeriod % _notificationGroupStride;
  final slotIndex = withinGroup ~/ _notificationSlotStride;
  final slots = period.allSlots;
  if (slotIndex >= slots.length) return null;
  final daysSinceEpoch = withinGroup % _notificationSlotStride;

  return (
    period: period,
    groupCode: groupCode,
    targetDate: DateTime.utc(1970).add(Duration(days: daysSinceEpoch)),
    alertTime: slots[slotIndex],
  );
}

/// 다음 주 식단을 읽지 못해 콘텐츠를 재생성할 수 없을 때도 현재 설정에서 이미
/// 제외된 pending은 보존하지 않는다. 메뉴 존재 여부만 알 수 없으므로, ID가 담는
/// 시간대·시각·요일·발송 그룹까지만 검증한다.
bool _matchesCurrentNotificationSettings(
  int id,
  NotificationSettings settings,
) {
  if (!settings.enabled) return false;
  final target = _ownedNotificationTarget(id);
  if (target == null) return false;

  final alertTime = settings.alertTimeOf(target.period);
  if (alertTime == null ||
      alertTime.hour != target.alertTime.hour ||
      alertTime.minute != target.alertTime.minute) {
    return false;
  }
  if (!settings.days.contains(
    DayOfWeek.values[target.targetDate.weekday - 1],
  )) {
    return false;
  }

  final deliverySettings = normalizeNotificationDeliverySettings(settings);
  if (deliverySettings.keywords.isNotEmpty) {
    return target.groupCode == 9 && deliverySettings.cafeterias.isNotEmpty;
  }
  return switch (target.groupCode) {
    0 => deliverySettings.dormMealTypes.contains(DormMenuType.korean),
    1 => deliverySettings.dormMealTypes.contains(DormMenuType.halal),
    2 => deliverySettings.cafeterias.contains(Cafeteria.student),
    3 => deliverySettings.cafeterias.contains(Cafeteria.faculty),
    _ => false,
  };
}

bool _idTargetsWeek(int id, DateTime weekStart) {
  final target = _ownedNotificationTarget(id);
  if (target == null) return false;
  final day = target.targetDate.difference(DateTime.utc(1970)).inDays;
  final start = DateTime.utc(
    weekStart.year,
    weekStart.month,
    weekStart.day,
  ).difference(DateTime.utc(1970)).inDays;
  return day >= start && day < start + 7;
}
