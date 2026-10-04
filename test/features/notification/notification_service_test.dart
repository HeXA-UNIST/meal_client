import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/settings/locale_settings.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/core/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({StorageKeys.locale: 'en'}),
  );

  test('업데이트 후 첫 실행 전 알림은 시스템 언어를 쓰되 저장하지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    expect(
      (await notificationLocalizations()).localeName,
      resolveInitialAppLocale(PlatformDispatcher.instance.locales).languageCode,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
    await prefs.setString(StorageKeys.locale, 'en');
    expect((await notificationLocalizations()).localeName, 'en');
  });
  test('Android 예약은 항상 inexactAllowWhileIdle을 사용한다', () async {
    AndroidScheduleMode? capturedMode;
    tz.TZDateTime? capturedDate;

    await scheduleAndroidMealNotification(
      id: 100000001,
      fireInstant: DateTime.utc(2026, 7, 20, 2),
      title: 'title',
      body: 'body',
      zonedSchedule:
          ({
            required id,
            required title,
            required body,
            required scheduledDate,
            required notificationDetails,
            required scheduleMode,
          }) async {
            capturedMode = scheduleMode;
            capturedDate = scheduledDate;
          },
    );

    expect(capturedMode, AndroidScheduleMode.inexactAllowWhileIdle);
    expect(capturedDate?.location, tz.UTC);
    expect(capturedDate?.toUtc(), DateTime.utc(2026, 7, 20, 2));
  });

  test('Android 앱 또는 meal 채널이 차단되면 권한 없음으로 판정한다', () {
    const mealBlocked = AndroidNotificationChannel(
      'meal',
      'Meal Notifications',
      importance: Importance.none,
    );

    expect(
      androidMealNotificationAuthorizationStatus(
        appNotificationsEnabled: false,
        channels: const [],
      ),
      MealNotificationAuthorizationStatus.notAuthorized,
    );
    expect(
      androidMealNotificationAuthorizationStatus(
        appNotificationsEnabled: true,
        channels: const [mealBlocked],
      ),
      MealNotificationAuthorizationStatus.notAuthorized,
    );
    expect(
      androidMealNotificationAuthorizationStatus(
        appNotificationsEnabled: true,
        channels: const [],
      ),
      MealNotificationAuthorizationStatus.enabled,
    );
  });

  test('Android 예약은 배치에서 전달한 채널 언어를 사용한다', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ko'});
    String? capturedName;
    await scheduleAndroidMealNotification(
      id: 100000001,
      fireInstant: DateTime.utc(2026, 7, 20, 2),
      title: 'title',
      body: 'body',
      channelName: 'Meal Notifications',
      zonedSchedule:
          ({
            required id,
            required title,
            required body,
            required scheduledDate,
            required notificationDetails,
            required scheduleMode,
          }) async {
            capturedName = notificationDetails?.channelName;
          },
    );
    expect(capturedName, 'Meal Notifications');
  });
}
