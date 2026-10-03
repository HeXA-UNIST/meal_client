import 'dart:io';

import 'package:workmanager/workmanager.dart';

import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/widget/widget_service.dart';

Future<void> initializeNativeServices() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  await refreshWidgets();

  await Workmanager().initialize(callbackDispatcher);
  await initializeMealBackgroundRefresh();
  await initNotifications();
}
