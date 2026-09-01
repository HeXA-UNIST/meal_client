import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
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

    final l10n = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(l10n.androidNotificationTimingNotice), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('월')),
      matchesSemantics(
        label: '월',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
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
        hasEnabledState: true,
        isEnabled: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('마스터 스위치가 꺼지면 종속 컨트롤이 선택 상태는 유지한 채 모두 비활성이 된다', (tester) async {
    final settings = await _pumpPage(
      tester,
      platform: MealNotificationPlatform.android,
      initialValues: {
        // 알림은 꺼진 상태지만 아침 시간대는 선택해 둔 이력이 있다.
        '${StorageKeys.notificationPeriodTimePrefix}'
                '${MealNotificationPeriod.morning.name}':
            '7:30',
      },
    );
    addTearDown(settings.dispose);

    expect(settings.notification.enabled, isFalse);
    final l10n = lookupAppLocalizations(const Locale('ko'));

    // 요일 토글: 선택 상태는 남기고 탭 액션은 노출하지 않는다.
    expect(
      tester.getSemantics(find.bySemanticsLabel('월')),
      matchesSemantics(
        label: '월',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        hasSelectedState: true,
        isSelected: true,
      ),
    );

    // 선택해 둔 시간대 스위치는 켜진 상태로 보이되 조작할 수 없다.
    final morningRow = find.ancestor(
      of: find.text(l10n.breakfast),
      matching: find.byType(ListTile),
    );
    final morningSwitch = tester.widget<Switch>(
      find.descendant(of: morningRow, matching: find.byType(Switch)),
    );
    expect(morningSwitch.value, isTrue);
    expect(morningSwitch.onChanged, isNull);
    // activeTrackColor를 넘기면 disabled 기본색을 덮어써 켜진 색이 그대로 남는다.
    expect(morningSwitch.activeTrackColor, isNull);

    final morningDropdown = tester.widget<DropdownButton<TimeOfDay>>(
      find.descendant(
        of: morningRow,
        matching: find.byType(DropdownButton<TimeOfDay>),
      ),
    );
    expect(morningDropdown.onChanged, isNull);

    // 식당 칩은 전부 비활성이지만 선택 상태는 그대로다.
    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    expect(chips, isNotEmpty);
    for (final chip in chips) {
      expect(chip.onSelected, isNull);
    }
    expect(chips.where((chip) => chip.selected), isNotEmpty);

    // 상위 알림 스위치 자체는 계속 조작할 수 있어야 한다.
    final masterSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(masterSwitch.onChanged, isNotNull);
    expect(masterSwitch.activeTrackColor, isNotNull);

    // 비활성 컨트롤을 탭해도 설정이 바뀌지 않는다.
    final daysBefore = settings.notification.days;
    final dormTypesBefore = settings.notification.dormMenuTypes;
    final alertTimesBefore = Map.of(settings.notification.alertTimes);

    await tester.tap(find.bySemanticsLabel('월'), warnIfMissed: false);
    await tester.tap(find.byType(FilterChip).first, warnIfMissed: false);
    await tester.tap(
      find.descendant(of: morningRow, matching: find.byType(Switch)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(settings.notification.days, daysBefore);
    expect(settings.notification.dormMenuTypes, dormTypesBefore);
    expect(settings.notification.alertTimes, alertTimesBefore);
    expect(settings.notification.enabled, isFalse);
  });

  testWidgets('알림을 켜둔 상태에서 시스템 권한이 꺼져 있으면 복구 경로가 노출된다', (tester) async {
    final settings = await _pumpPage(
      tester,
      platform: MealNotificationPlatform.android,
      initialValues: {StorageKeys.notificationEnabled: true},
      authorization: MealNotificationAuthorizationStatus.notAuthorized,
      permissionGranted: false,
    );
    addTearDown(settings.dispose);
    await tester.pump();

    final l10n = lookupAppLocalizations(const Locale('ko'));
    final recoveryTile = find.widgetWithIcon(
      ListTile,
      Icons.notifications_off_outlined,
    );
    expect(recoveryTile, findsOneWidget);
    expect(
      find.descendant(
        of: recoveryTile,
        matching: find.text(l10n.notificationPermissionUnavailable),
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, l10n.openSystemAppSettings),
      findsOneWidget,
    );
  });

  testWidgets('알림을 켜지 않았으면 권한 안내 섹션이 없고 토글 시 SnackBar로 안내한다', (tester) async {
    final settings = await _pumpPage(
      tester,
      platform: MealNotificationPlatform.android,
      authorization: MealNotificationAuthorizationStatus.notAuthorized,
      permissionGranted: false,
    );
    addTearDown(settings.dispose);
    await tester.pump();

    expect(
      find.widgetWithIcon(ListTile, Icons.notifications_off_outlined),
      findsNothing,
    );

    final l10n = lookupAppLocalizations(const Locale('ko'));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(settings.notification.enabled, isFalse);
    expect(
      find.widgetWithIcon(ListTile, Icons.notifications_off_outlined),
      findsNothing,
    );
    expect(find.text(l10n.notificationPermissionDenied), findsOneWidget);
    expect(
      find.widgetWithText(SnackBarAction, l10n.openSystemAppSettings),
      findsOneWidget,
    );
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

    final l10n = lookupAppLocalizations(const Locale('ko'));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(settings.notification.enabled, isFalse);
    expect(find.text(l10n.notificationSyncFailed), findsWidgets);
    expect(find.text(l10n.notificationPermissionDenied), findsNothing);

    final retryRow = find.ancestor(
      of: find.text(l10n.notificationSyncFailed),
      matching: find.byType(ListTile),
    );
    final retryButton = find.widgetWithText(SnackBarAction, l10n.retry);
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
