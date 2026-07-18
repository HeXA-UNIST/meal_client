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

const _kstOffset = Duration(hours: 9);

/// [enabledDays]의 메뉴 요일에 해당하는 가장 가까운 실행 시각을 반환한다.
///
/// Workmanager의 실행 시각은 기기 현지 시간이지만, 메뉴와 워커의 요일 판정은
/// KST를 사용한다. 따라서 후보 시각을 KST로 환산한 뒤 메뉴 대상 요일을 비교한다.
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
    final kstCandidate = candidate.toUtc().add(_kstOffset);
    final targetDay = notificationTargetDayFor(period, kstCandidate);
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

/// 지정한 [period]의 다음 알림을 [alertTime]에 실행되도록 등록한다.
/// 워커가 실행을 마치면 워커 자신이 다음 활성 메뉴 요일로 태스크를 재등록한다.
Future<void> scheduleKeywordNotificationFor(
  MealAlertPeriod period,
  TimeOfDay alertTime,
  Set<DayOfWeek> enabledDays,
) async {
  final taskName = taskNameOf(period);
  try {
    await Workmanager().cancelByUniqueName(taskName);

    final now = DateTime.now();
    final next = nextEnabledFireTime(
      period: period,
      alertTime: alertTime,
      enabledDays: enabledDays,
      now: now,
    );
    if (next == null) return;
    final delay = next.difference(now);

    assert(() {
      debugPrint(
        '[BapU] ${period.name} scheduled at $next '
        '(in ${delay.inMinutes}m ${delay.inSeconds % 60}s)',
      );
      return true;
    }());

    await Workmanager().registerOneOffTask(
      taskName,
      taskName,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (e, st) {
    assert(() {
      debugPrint('[BapU] schedule failed for ${period.name}: $e\n$st');
      return true;
    }());
  }
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
