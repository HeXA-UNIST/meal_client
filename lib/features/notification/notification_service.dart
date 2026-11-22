import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:meal_client/core/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/features/settings/locale_settings.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_platform.dart';

const _channelId = 'meal';
const _androidNotificationIcon = 'ic_stat_bapu';
final _plugin = FlutterLocalNotificationsPlugin();

Future<AppLocalizations> notificationLocalizations() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  // 최초 언어 저장과 이관은 앱 시작에서만 수행한다.
  return lookupAppLocalizations(await readAppLocale(prefs));
}

Future<void> initNotifications({AppLocalizations? l10n}) async {
  const androidInit = AndroidInitializationSettings(_androidNotificationIcon);

  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  await _plugin.initialize(
    settings: const InitializationSettings(android: androidInit, iOS: iosInit),
  );
  await refreshMealNotificationChannel(l10n: l10n);
}

Future<void> refreshMealNotificationChannel({AppLocalizations? l10n}) async {
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return;
  final channelName =
      (l10n ?? await notificationLocalizations()).mealNotifications;
  // 같은 ID로 등록하면 이름만 갱신되고 사용자가 정한 채널 설정은 보존된다.
  await android.createNotificationChannel(
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
  exactAlarmNotAuthorized,
  notApplicable;

  bool get needsPermission =>
      this == notAuthorized || this == exactAlarmNotAuthorized;
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
      final status = androidMealNotificationAuthorizationStatus(
        appNotificationsEnabled: true,
        channels: await android.getNotificationChannels(),
      );
      if (status != MealNotificationAuthorizationStatus.enabled) return status;
      // 알림 표시 권한과 정확한 알람 특별 접근은 별개다.
      return await android.canScheduleExactNotifications() ?? false
          ? MealNotificationAuthorizationStatus.enabled
          : MealNotificationAuthorizationStatus.exactAlarmNotAuthorized;
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

typedef AndroidZonedSchedule = Future<void> Function({
  required int id,
  required String? title,
  required String? body,
  required tz.TZDateTime scheduledDate,
  required AndroidNotificationDetails? notificationDetails,
  required AndroidScheduleMode scheduleMode,
  String? payload,
});

/// 플러그인에 저장된 pending 본문과 함께 비교할 예약 시각·모드·채널 정보다.
/// 버전은 예약 모드나 표시 옵션을 바꿀 때 올려 기존 예약도 다시 등록한다.
String androidMealNotificationSchedulePayload({
  required DateTime fireInstant,
  required String channelName,
  required String alarmGeneration,
}) => jsonEncode([
  1,
  'exactAllowWhileIdle',
  fireInstant.millisecondsSinceEpoch,
  channelName,
  alarmGeneration,
]);

Future<String> readAndroidMealAlarmGeneration() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getString(StorageKeys.androidMealAlarmGeneration) ?? '';
}

Future<void> scheduleAndroidMealNotification({
  required int id,
  required DateTime fireInstant,
  required String title,
  required String body,
  AndroidZonedSchedule? zonedSchedule,
  String? channelName,
  Future<bool> Function()? canScheduleExact,
  String? alarmGeneration,
}) async {
  final resolvedChannelName =
      channelName ?? (await notificationLocalizations()).mealNotifications;
  final schedule =
      zonedSchedule ??
      _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.zonedSchedule;
  if (schedule == null) return;
  if (!await (canScheduleExact ?? canScheduleExactMealNotifications)()) {
    throw PlatformException(code: 'exact_alarms_not_permitted');
  }
  final generation = alarmGeneration ?? await readAndroidMealAlarmGeneration();
  await schedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: tz.TZDateTime.from(fireInstant, tz.UTC),
    notificationDetails: AndroidNotificationDetails(
      _channelId,
      resolvedChannelName,
      icon: _androidNotificationIcon,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    ),
    scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: androidMealNotificationSchedulePayload(
      fireInstant: fireInstant,
      channelName: resolvedChannelName,
      alarmGeneration: generation,
    ),
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
  return (await androidPendingMealNotificationRequests())
      .map((request) => request.id)
      .toList(growable: false);
}

Future<List<PendingNotificationRequest>>
androidPendingMealNotificationRequests() async {
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android == null) return const [];
  return android.pendingNotificationRequests();
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
  String? channelName,
  String? androidAlarmGeneration,
}) => switch (platform ?? mealNotificationPlatform) {
  MealNotificationPlatform.android => scheduleAndroidMealNotification(
    id: id,
    fireInstant: fireInstant,
    title: title,
    body: body,
    channelName: channelName,
    alarmGeneration: androidAlarmGeneration,
  ),
  MealNotificationPlatform.ios => scheduleIosMealNotification(
    id: id,
    fireInstant: fireInstant,
    title: title,
    body: body,
  ),
  MealNotificationPlatform.unsupported => Future.value(),
};

Future<bool> canScheduleExactMealNotifications() async =>
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.canScheduleExactNotifications() ??
    false;

/// Android 12 이상에서는 시스템의 알람 및 리마인더 화면에서 허용한다.
Future<bool> requestExactMealAlarmPermission() async =>
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission() ??
    false;

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

Future<void> openMealNotificationSettings() async {
  await _plugin.openAppNotificationSettings();
}
