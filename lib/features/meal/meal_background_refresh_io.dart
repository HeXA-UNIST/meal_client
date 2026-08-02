import 'dart:io';

import 'package:workmanager/workmanager.dart';

const mealRefreshTaskName = 'bapu_meal_refresh';
const mealRefreshTaskFrequency = Duration(hours: 1);

Future<void> initializeMealBackgroundRefresh() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }

  // Workmanager 초기화는 앱의 단일 callbackDispatcher에서 수행한다.
  await Workmanager().registerPeriodicTask(
    mealRefreshTaskName,
    mealRefreshTaskName,
    frequency: mealRefreshTaskFrequency,
    // iOS BGAppRefreshTask는 Workmanager 네트워크 제약을 강제하지 않는다.
    constraints: Platform.isAndroid
        ? Constraints(networkType: NetworkType.connected)
        : null,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
