import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
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
}
