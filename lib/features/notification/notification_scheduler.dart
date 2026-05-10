import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';

const kMealKeywordTaskName = 'meal_keyword_check';

/// 다음 [alertTime](기기 로컬 시각)까지 남은 시간을 초기 지연으로 설정하고,
/// 이후 24시간마다 반복 실행되는 Workmanager 태스크를 등록한다.
/// 기기 시간대가 KST로 설정되어 있다고 가정한다(UNIST 앱 특성상 한국 사용자 전용).
Future<void> scheduleKeywordNotification(TimeOfDay alertTime) async {
  // ExistingPeriodicWorkPolicy.replace 만으로는 재등록 시 기존 스케줄이
  // 그대로 살아있는 경우가 있어, 명시적으로 먼저 취소한 뒤 새로 등록한다.
  await Workmanager().cancelByUniqueName(kMealKeywordTaskName);

  final now = DateTime.now();
  var next = DateTime(now.year, now.month, now.day,
      alertTime.hour, alertTime.minute);
  if (!next.isAfter(now)) {
    next = next.add(const Duration(days: 1));
  }

  await Workmanager().registerPeriodicTask(
    kMealKeywordTaskName,
    kMealKeywordTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: next.difference(now),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
}

Future<void> cancelKeywordNotification() =>
    Workmanager().cancelByUniqueName(kMealKeywordTaskName);
