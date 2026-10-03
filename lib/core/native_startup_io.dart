import 'dart:io';

import 'package:workmanager/workmanager.dart';

import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/features/settings/locale_settings.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/features/widget/widget_service.dart';

Future<void> initializeNativeServices() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  final prefs = await SharedPreferences.getInstance();
  await saveSharedWidgetFileAsString(
    StorageKeys.widgetLocaleFile,
    loadAppLocale(prefs).languageCode,
  );
  await refreshWidgets();

  await Workmanager().initialize(callbackDispatcher);
  await initializeMealBackgroundRefresh();
  await initNotifications();
}
