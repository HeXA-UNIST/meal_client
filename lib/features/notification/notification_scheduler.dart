import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';

const kMealKeywordTaskName = 'meal_keyword_check';

/// 다음 [alertTime](KST)까지 남은 시간을 초기 지연으로 설정하고,
/// 이후 24시간마다 반복 실행되는 Workmanager 태스크를 등록한다.
Future<void> scheduleKeywordNotification(TimeOfDay alertTime) async {
  final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  var next = DateTime(
    kstNow.year, kstNow.month, kstNow.day,
    alertTime.hour, alertTime.minute,
  );
  if (!next.isAfter(kstNow)) {
    next = next.add(const Duration(days: 1));
  }

  await Workmanager().registerPeriodicTask(
    kMealKeywordTaskName,
    kMealKeywordTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: next.difference(kstNow),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
}

Future<void> cancelKeywordNotification() =>
    Workmanager().cancelByUniqueName(kMealKeywordTaskName);
