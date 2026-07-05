import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';
import 'package:meal_client/features/widget/widget_service.dart';
import 'package:workmanager/workmanager.dart';

const mealRefreshTaskName = 'bapu_meal_refresh';
const mealRefreshTaskFrequency = Duration(hours: 1);

@pragma('vm:entry-point')
void mealBackgroundRefreshDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    if (taskName != mealRefreshTaskName &&
        taskName != Workmanager.iOSBackgroundTask) {
      return true;
    }

    try {
      await MealRefreshService(throwOnCacheWriteFailure: true).refreshMealData();
      await InfoRefreshService(throwOnCacheWriteFailure: true).refreshInfo();
      await refreshWidgets(throwOnFailure: true);
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
