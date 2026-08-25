import 'package:app_settings/app_settings.dart' show AppSettingsType;
import 'package:app_settings/app_settings_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:meal_client/features/settings/settings_page.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Android에서 앱 언어 설정 화면을 연다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final platform = _FakeAppSettingsPlatform();
      final previousPlatform = AppSettingsPlatform.instance;
      AppSettingsPlatform.instance = platform;
      addTearDown(() => AppSettingsPlatform.instance = previousPlatform);

      final settings = await _pumpSettingsPage(tester, const Locale('ko'));
      addTearDown(settings.dispose);

      final l10n = lookupAppLocalizations(const Locale('ko'));
      final languageTile = find.widgetWithText(
        ListTile,
        l10n.appLanguageSettings,
      );
      await tester.scrollUntilVisible(languageTile, 200);
      await tester.tap(languageTile);
      await tester.pump();

      expect(platform.openedType, AppSettingsType.appLocale);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }, skip: kIsWeb);

  testWidgets('iOS에서 앱 설정 화면을 연다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final platform = _FakeAppSettingsPlatform();
      final previousPlatform = AppSettingsPlatform.instance;
      AppSettingsPlatform.instance = platform;
      addTearDown(() => AppSettingsPlatform.instance = previousPlatform);

      final settings = await _pumpSettingsPage(tester, const Locale('en'));
      addTearDown(settings.dispose);

      final l10n = lookupAppLocalizations(const Locale('en'));
      final languageTile = find.widgetWithText(
        ListTile,
        l10n.appLanguageSettings,
      );
      await tester.scrollUntilVisible(languageTile, 200);
      await tester.tap(languageTile);
      await tester.pump();

      expect(platform.openedType, AppSettingsType.settings);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }, skip: kIsWeb);

  testWidgets('웹에서는 언어 설정 섹션을 표시하지 않는다', (tester) async {
    final settings = await _pumpSettingsPage(tester, const Locale('ko'));
    addTearDown(settings.dispose);

    final l10n = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(l10n.language), findsNothing);
    expect(find.text(l10n.appLanguageSettings), findsNothing);
  }, skip: !kIsWeb);
}

Future<AppSettings> _pumpSettingsPage(
  WidgetTester tester,
  Locale locale,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings(
    prefs,
    notificationPlatform: MealNotificationPlatform.unsupported,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsPage(),
      ),
    ),
  );
  return settings;
}

class _FakeAppSettingsPlatform extends AppSettingsPlatform {
  AppSettingsType? openedType;

  @override
  Future<void> openAppSettings({
    AppSettingsType type = AppSettingsType.settings,
    bool asAnotherTask = false,
  }) async {
    openedType = type;
  }
}
