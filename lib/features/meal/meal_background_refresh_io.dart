import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';
import 'package:workmanager/workmanager.dart';

const mealRefreshTaskName = 'bapu_meal_refresh';
const mealRefreshTaskFrequency = Duration(hours: 1);

@pragma('vm:entry-point')
void mealBackgroundRefreshDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (taskName != mealRefreshTaskName &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }

    try {
      await MealRefreshService().refreshMealData();
      return true;
    } catch (e) {
      debugPrint('[BapU] background meal refresh failed: $e');
      return false;
    }
  });
}

Future<void> initializeMealBackgroundRefresh() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }

  await Workmanager().initialize(mealBackgroundRefreshDispatcher);
  await Workmanager().registerPeriodicTask(
    mealRefreshTaskName,
    mealRefreshTaskName,
    frequency: mealRefreshTaskFrequency,
    // iOS BGAppRefreshTask does not enforce Workmanager network constraints.
    constraints: Platform.isAndroid
        ? Constraints(networkType: NetworkType.connected)
        : null,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
