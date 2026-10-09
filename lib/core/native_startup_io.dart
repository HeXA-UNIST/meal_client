import 'dart:io';

import 'package:workmanager/workmanager.dart';

import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/l10n/app_localizations.dart';

Future<void> initializeNativeServices({AppLocalizations? l10n}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  await Workmanager().initialize(callbackDispatcher);
  await initializeMealBackgroundRefresh();
  await initNotifications(l10n: l10n);
}
