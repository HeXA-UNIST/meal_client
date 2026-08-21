import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale, basicLocaleListResolution;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

const _channelId = 'meal';
final _plugin = FlutterLocalNotificationsPlugin();

AppLocalizations notificationLocalizations() {
  return resolveNotificationLocalizations(PlatformDispatcher.instance.locales);
}

AppLocalizations resolveNotificationLocalizations(
  List<Locale> preferredLocales,
) {
  final locale = basicLocaleListResolution(
    preferredLocales.isEmpty ? const [Locale('ko')] : preferredLocales,
    AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(locale);
}

Future<void> initNotifications() async {
  final channelName = notificationLocalizations().mealNotifications;
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
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

/// iOS 플러그인은 권한을 아직 묻지 않은 상태와 거부 상태를 구분해 주지 않는다.
enum MealNotificationAuthorizationStatus {
  enabled,
  notAuthorized,
  notApplicable,
}

Future<MealNotificationAuthorizationStatus>
mealNotificationAuthorizationStatus() async {
  final permissions = await _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()
      ?.checkPermissions();
  if (permissions == null) {
    return MealNotificationAuthorizationStatus.notApplicable;
  }
  return permissions.isAlertEnabled
      ? MealNotificationAuthorizationStatus.enabled
      : MealNotificationAuthorizationStatus.notAuthorized;
}

const _scheduledMealNotificationDetails = DarwinNotificationDetails(
  presentAlert: true,
  presentBadge: true,
  presentSound: true,
  interruptionLevel: InterruptionLevel.active,
);

Future<void> scheduleMealNotification({
  required int id,
  required DateTime fireInstant,
  required String title,
  required String body,
  DarwinNotificationDetails? notificationDetails,
}) async {
  final ios = _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  if (ios == null) return;
  await ios.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: tz.TZDateTime.from(fireInstant, tz.UTC),
    notificationDetails:
        notificationDetails ?? _scheduledMealNotificationDetails,
  );
}

Future<List<int>> pendingNotificationIds() async {
  final ios = _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  if (ios == null) return const [];
  return (await ios.pendingNotificationRequests())
      .map((request) => request.id)
      .toList(growable: false);
}

Future<void> cancelPendingNotification(int id) async {
  await _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()
      ?.cancel(id: id);
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
      interruptionLevel: InterruptionLevel.active,
    ),
  );
  await _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: details,
  );
}
