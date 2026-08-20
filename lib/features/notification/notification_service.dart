import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:meal_client/l10n/app_localizations.dart';

const _channelId = 'meal';
final _plugin = FlutterLocalNotificationsPlugin();

AppLocalizations notificationLocalizations() {
  final locale = basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(locale);
}

Future<void> initNotifications() async {
  final channelName = notificationLocalizations().mealNotifications;
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  await _plugin.initialize(
    settings: const InitializationSettings(android: androidInit, iOS: iosInit),
  );
  await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          channelName,
          importance: Importance.defaultImportance,
        ),
      );
}

Future<bool> requestNotificationPermission() async {
  final androidGranted = await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  final iosGranted = await _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()
      ?.requestPermissions(alert: true, badge: true, sound: true);

  return androidGranted ?? iosGranted ?? false;
}

Future<void> showMealNotification({
  required int id,
  required String title,
  required String body,
}) async {
  final channelName = notificationLocalizations().mealNotifications;
  // 식당별 메뉴 또는 여러 키워드 결과를 펼쳐 볼 수 있게 한다.
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );
  await _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: details,
  );
}
