import 'dart:io' show Platform;

import 'notification_platform_type.dart';

MealNotificationPlatform get mealNotificationPlatform {
  if (Platform.isIOS) return MealNotificationPlatform.ios;
  if (Platform.isAndroid) return MealNotificationPlatform.android;
  return MealNotificationPlatform.unsupported;
}
