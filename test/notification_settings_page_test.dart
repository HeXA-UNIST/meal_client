import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:meal_client/features/settings/notification/notification_settings_page.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('알림 시간과 요일의 적응형 UI 스타일을 적용한다', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      StorageKeys.notificationEnabled: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(
      prefs,
      notificationScheduleCoordinator: NotificationScheduleCoordinator(
        schedule:
            (
              settings, {
              required clearPendingFirst,
              required isCurrent,
              currentWeek,
            }) async {},
        cancel: () async {},
      ),
      notificationPermissionRequester: () async => true,
    );
    addTearDown(settings.dispose);

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

    const notificationSubtitle = '선택한 식당과 시간대에 맞춰 푸시 알림을 보내드립니다.';
    ListTile notificationTile() => tester.widget<ListTile>(
      find.ancestor(of: find.text('식단 알림'), matching: find.byType(ListTile)),
    );
    expect((notificationTile().subtitle! as Text).data, notificationSubtitle);

    final keywordField = tester.widget<TextField>(find.byType(TextField));
    expect(keywordField.decoration?.labelText, '키워드');
    expect(keywordField.decoration?.hintText, '메뉴 키워드를 입력하세요.');
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .tooltip,
      '키워드 추가',
    );

    settings.addNotificationKeyword('라면');
    await tester.pump();

    expect((notificationTile().subtitle! as Text).data, notificationSubtitle);

    const guidance = '알림 받을 시간대를 하나 이상 켜주세요.';
    expect(find.text(guidance), findsOneWidget);

    final morningTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('아침'), matching: find.byType(ListTile)),
    );
    expect(morningTile.contentPadding, const EdgeInsets.fromLTRB(16, 0, 24, 0));

    final dropdownFinder = find.byType(DropdownButton<TimeOfDay>);
    expect(dropdownFinder, findsNWidgets(4));
    final colorScheme = Theme.of(
      tester.element(find.byType(MealNotificationPage)),
    ).colorScheme;
    for (final dropdown in tester.widgetList<DropdownButton<TimeOfDay>>(
      dropdownFinder,
    )) {
      expect(dropdown.borderRadius, BorderRadius.circular(8));
      expect(dropdown.elevation, 2);
      expect(dropdown.dropdownColor, colorScheme.surfaceContainer);
    }
    expect(
      Theme.of(tester.element(dropdownFinder.first)).focusColor,
      colorScheme.onSurface.withValues(alpha: 0.08),
    );

    final mondayFinder = find.text('월');
    final tuesdayFinder = find.text('화');
    expect(
      tester.getCenter(tuesdayFinder).dx - tester.getCenter(mondayFinder).dx,
      closeTo((560 - 42) / 6, 0.01),
    );

    tester.view.physicalSize = const Size(400, 1200);
    await tester.pump();

    expect(
      find.ancestor(
        of: mondayFinder,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(tuesdayFinder).dx - tester.getCenter(mondayFinder).dx,
      60,
    );

    await tester.tap(find.byType(Switch).at(1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(guidance), findsNothing);
  });

  testWidgets('권한 상태를 구분할 수 없으면 중립 안내와 지속 설정 경로를 표시한다', (tester) async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.notificationEnabled: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(
      prefs,
      notificationScheduleCoordinator: NotificationScheduleCoordinator(
        schedule:
            (
              settings, {
              required clearPendingFirst,
              required isCurrent,
              currentWeek,
            }) async {},
        cancel: () async {},
      ),
      notificationPermissionRequester: () async => true,
      notificationAuthorizationStatusReader: () async =>
          MealNotificationAuthorizationStatus.notAuthorized,
    );
    addTearDown(settings.dispose);
    await settings.refreshNotificationAuthorizationStatus();

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

    expect(
      find.text('알림이 현재 표시되지 않을 수 있습니다. 시스템 설정에서 권한을 확인해주세요.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, '설정 열기'), findsOneWidget);
  });
}
