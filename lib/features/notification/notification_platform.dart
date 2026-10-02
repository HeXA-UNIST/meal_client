import 'notification_platform_stub.dart'
    if (dart.library.io) 'dart:io'
    as platform;

enum MealNotificationPlatform { android, ios, unsupported }

MealNotificationPlatform get mealNotificationPlatform {
  if (platform.Platform.isIOS) return MealNotificationPlatform.ios;
  if (platform.Platform.isAndroid) return MealNotificationPlatform.android;
  return MealNotificationPlatform.unsupported;
}
