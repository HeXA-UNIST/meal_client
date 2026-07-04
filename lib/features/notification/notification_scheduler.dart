import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';

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

/// 지정한 [period]의 다음 알림을 [alertTime]에 실행되도록 등록한다.
/// 워커가 실행을 마치면 워커 자신이 같은 시각으로 다음날 태스크를 재등록한다.
Future<void> scheduleKeywordNotificationFor(
  MealAlertPeriod period,
  TimeOfDay alertTime,
) async {
  final taskName = taskNameOf(period);
  try {
    await Workmanager().cancelByUniqueName(taskName);

    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day,
        alertTime.hour, alertTime.minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
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
) async {
  for (final period in MealAlertPeriod.values) {
    final time = alertTimes[period];
    if (time == null) {
      await cancelKeywordNotificationFor(period);
    } else {
      await scheduleKeywordNotificationFor(period, time);
    }
  }
}

/// 모든 시간대 태스크를 취소한다.
Future<void> cancelAllKeywordNotifications() async {
  for (final period in MealAlertPeriod.values) {
    await cancelKeywordNotificationFor(period);
  }
}
