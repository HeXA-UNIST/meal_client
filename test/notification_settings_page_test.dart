import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:meal_client/features/settings/notification/notification_settings_page.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Android 지연 안내와 요일 선택 의미를 노출한다', (tester) async {
    final settings = await _pumpPage(
      tester,
      platform: MealNotificationPlatform.android,
      initialValues: {StorageKeys.notificationEnabled: true},
    );
    addTearDown(settings.dispose);

    expect(
      find.text('Android에서는 기기 절전 상태에 따라 알림이 선택한 시각보다 늦게 도착할 수 있습니다.'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('월')),
      matchesSemantics(
        label: '월',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('월'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.bySemanticsLabel('월')),
      matchesSemantics(
        label: '월',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('설정 진입 시 권한 상태를 읽고 복구 경로를 표시한다', (tester) async {
    final settings = await _pumpPage(
      tester,
      platform: MealNotificationPlatform.android,
      authorization: MealNotificationAuthorizationStatus.notAuthorized,
      permissionGranted: false,
    );
    addTearDown(settings.dispose);
    await tester.pump();

    expect(
      find.text('알림이 현재 표시되지 않을 수 있습니다. 시스템 설정에서 권한을 확인해주세요.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, '설정 열기'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('알림 권한이 차단되었습니다. 설정에서 허용해주세요.'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, '설정 열기'), findsOneWidget);
  });

  testWidgets('예약 실패를 권한 거부와 구분하고 다시 시도할 수 있다', (tester) async {
    var shouldFail = true;
    final settings = await _pumpPage(
      tester,
      platform: MealNotificationPlatform.android,
      schedule: (settings, {required isCurrent}) async {
        if (shouldFail) throw StateError('schedule failed');
      },
    );
    addTearDown(settings.dispose);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(settings.notification.enabled, isFalse);
    expect(find.text('알림 설정을 적용하지 못했습니다.'), findsWidgets);
    expect(find.text('알림 권한이 차단되었습니다. 설정에서 허용해주세요.'), findsNothing);

    final retryRow = find.ancestor(
      of: find.text('알림 설정을 적용하지 못했습니다.'),
      matching: find.byType(ListTile),
    );
    final retryButton = find.widgetWithText(SnackBarAction, '다시 시도');
    shouldFail = false;
    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(settings.notification.enabled, isTrue);
    expect(settings.notificationSyncFailed, isFalse);
    expect(retryRow, findsNothing);
  });
}

Future<AppSettings> _pumpPage(
  WidgetTester tester, {
  required MealNotificationPlatform platform,
  Map<String, Object> initialValues = const {},
  MealNotificationAuthorizationStatus authorization =
      MealNotificationAuthorizationStatus.enabled,
  bool permissionGranted = true,
  MealNotificationScheduler? schedule,
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings(
    prefs,
    notificationPlatform: platform,
    resumeListenerRegistrar: (_) => () {},
    notificationScheduleCoordinator: NotificationScheduleCoordinator(
      debounce: Duration.zero,
      schedule: schedule ?? (settings, {required isCurrent}) async {},
      cancel: () async {},
    ),
    notificationPermissionRequester: () async => permissionGranted,
    notificationAuthorizationStatusReader: () async => authorization,
  );

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: settings,
      child: const MaterialApp(
        locale: Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MealNotificationPage(),
      ),
    ),
  );
  return settings;
}
