import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:meal_client/features/notification/notification_platform.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/core/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({StorageKeys.locale: 'en'}),
  );

  test('Android 예약은 권한이 있으면 exactAllowWhileIdle 모드를 사용한다', () async {
    AndroidScheduleMode? capturedMode;
    tz.TZDateTime? capturedDate;

    await scheduleAndroidMealNotification(
      canScheduleExact: () async => true,
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
            payload,
          }) async {
            capturedMode = scheduleMode;
            capturedDate = scheduledDate;
          },
    );

    expect(capturedMode, AndroidScheduleMode.exactAllowWhileIdle);
    expect(capturedDate?.location, tz.UTC);
    expect(capturedDate?.toUtc(), DateTime.utc(2026, 7, 20, 2));
  });

  test('정확한 알람 권한이 없으면 부정확한 예약으로 대체하지 않는다', () async {
    var scheduled = false;
    await expectLater(
      scheduleAndroidMealNotification(
        id: 100000001,
        fireInstant: DateTime.utc(2026, 7, 20, 2),
        title: 'title',
        body: 'body',
        canScheduleExact: () async => false,
        zonedSchedule:
            ({
              required id,
              required title,
              required body,
              required scheduledDate,
              required notificationDetails,
              required scheduleMode,
              payload,
            }) async {
              scheduled = true;
            },
      ),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'exact_alarms_not_permitted',
        ),
      ),
    );
    expect(scheduled, isFalse);
  });

  test('Android 알림 표시 허용과 정확한 알람 특별 접근을 구분한다', () async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    var notificationsAllowed = true;
    var exactAllowed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'areNotificationsEnabled' => notificationsAllowed,
            'getNotificationChannels' => <Object>[],
            'canScheduleExactNotifications' => exactAllowed,
            _ => throw StateError('예상하지 않은 호출: ${call.method}'),
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(
      await mealNotificationAuthorizationStatus(
        platform: MealNotificationPlatform.android,
      ),
      MealNotificationAuthorizationStatus.exactAlarmNotAuthorized,
    );
    exactAllowed = true;
    expect(
      await mealNotificationAuthorizationStatus(
        platform: MealNotificationPlatform.android,
      ),
      MealNotificationAuthorizationStatus.enabled,
    );
    notificationsAllowed = false;
    expect(
      await mealNotificationAuthorizationStatus(
        platform: MealNotificationPlatform.android,
      ),
      MealNotificationAuthorizationStatus.notAuthorized,
    );
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
}
