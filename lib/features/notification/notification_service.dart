import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'meal';
const _channelName = '식단 알림';
final _plugin = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
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
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
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
  // 식당별 메뉴 또는 여러 키워드 결과를 펼쳐 볼 수 있게 한다.
  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
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
