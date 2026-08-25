import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale, basicLocaleListResolution;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_platform.dart';

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
mealNotificationAuthorizationStatus({
  MealNotificationPlatform? platform,
}) async {
  switch (platform ?? mealNotificationPlatform) {
    case MealNotificationPlatform.android:
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) {
        return MealNotificationAuthorizationStatus.notApplicable;
      }
      // 앱 알림 자체가 꺼져 있으면 채널을 더 볼 필요가 없다.
      // 채널 조회는 네이티브 왕복이라 결과가 정해진 경우엔 건너뛴다.
      if (!(await android.areNotificationsEnabled() ?? false)) {
        return MealNotificationAuthorizationStatus.notAuthorized;
      }
      return androidMealNotificationAuthorizationStatus(
        appNotificationsEnabled: true,
        channels: await android.getNotificationChannels(),
      );
    case MealNotificationPlatform.ios:
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
    case MealNotificationPlatform.unsupported:
      return MealNotificationAuthorizationStatus.notApplicable;
  }
}

MealNotificationAuthorizationStatus androidMealNotificationAuthorizationStatus({
  required bool appNotificationsEnabled,
  required List<AndroidNotificationChannel>? channels,
}) {
  if (!appNotificationsEnabled) {
    return MealNotificationAuthorizationStatus.notAuthorized;
  }
  final mealChannel = channels
      ?.where((channel) => channel.id == _channelId)
      .firstOrNull;
  return mealChannel?.importance == Importance.none
      ? MealNotificationAuthorizationStatus.notAuthorized
      : MealNotificationAuthorizationStatus.enabled;
}

const _scheduledMealNotificationDetails = DarwinNotificationDetails(
  presentAlert: true,
  presentBadge: true,
  presentSound: true,
  interruptionLevel: InterruptionLevel.active,
);

Future<void> scheduleIosMealNotification({
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

typedef AndroidZonedSchedule =
    Future<void> Function({
      required int id,
      required String? title,
      required String? body,
      required tz.TZDateTime scheduledDate,
      required AndroidNotificationDetails? notificationDetails,
      required AndroidScheduleMode scheduleMode,
    });

Future<void> scheduleAndroidMealNotification({
  required int id,
  required DateTime fireInstant,
  required String title,
  required String body,
  AndroidZonedSchedule? zonedSchedule,
}) async {
  final channelName = notificationLocalizations().mealNotifications;
  final schedule =
      zonedSchedule ??
      _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.zonedSchedule;
  if (schedule == null) return;
  await schedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: tz.TZDateTime.from(fireInstant, tz.UTC),
    notificationDetails: AndroidNotificationDetails(
      _channelId,
      channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    ),
    scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

Future<List<int>> iosPendingNotificationIds() async {
  final ios = _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  if (ios == null) return const [];
  return (await ios.pendingNotificationRequests())
      .map((request) => request.id)
      .toList(growable: false);
}

Future<List<int>> androidPendingNotificationIds() async {
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return const [];
  return (await android.pendingNotificationRequests())
      .map((request) => request.id)
      .toList(growable: false);
}

Future<void> cancelIosPendingNotification(int id) async {
  await _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()
      ?.cancel(id: id);
}

Future<void> cancelAndroidPendingNotification(int id) async {
  await _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.cancel(id: id);
}

Future<List<int>> pendingMealNotificationIds({
  MealNotificationPlatform? platform,
}) => switch (platform ?? mealNotificationPlatform) {
  MealNotificationPlatform.android => androidPendingNotificationIds(),
  MealNotificationPlatform.ios => iosPendingNotificationIds(),
  MealNotificationPlatform.unsupported => Future.value(const []),
};

Future<void> cancelPendingMealNotification(
  int id, {
  MealNotificationPlatform? platform,
}) => switch (platform ?? mealNotificationPlatform) {
  MealNotificationPlatform.android => cancelAndroidPendingNotification(id),
  MealNotificationPlatform.ios => cancelIosPendingNotification(id),
  MealNotificationPlatform.unsupported => Future.value(),
};

Future<void> scheduleMealNotification({
  required int id,
  required DateTime fireInstant,
  required String title,
  required String body,
  MealNotificationPlatform? platform,
}) => switch (platform ?? mealNotificationPlatform) {
  MealNotificationPlatform.android => scheduleAndroidMealNotification(
    id: id,
    fireInstant: fireInstant,
    title: title,
    body: body,
  ),
  MealNotificationPlatform.ios => scheduleIosMealNotification(
    id: id,
    fireInstant: fireInstant,
    title: title,
    body: body,
  ),
  MealNotificationPlatform.unsupported => Future.value(),
};

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
