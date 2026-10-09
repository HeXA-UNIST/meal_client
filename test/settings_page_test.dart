import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/settings/bapu_settings.dart';
import 'package:meal_client/features/settings/settings_page.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('앱 안에서 언어를 전환하면 화면에 반영한다', (tester) async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ko'});
    final prefs = await SharedPreferences.getInstance();
    final settings = BapuSettings(
      prefs,
      notificationPlatform: MealNotificationPlatform.unsupported,
    );
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Consumer<BapuSettings>(
          builder: (context, settings, _) => MaterialApp(
            locale: settings.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsPage(),
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.text('English'), 150);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).settings),
      findsOneWidget,
    );
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    expect(
      find.text(lookupAppLocalizations(const Locale('ko')).settings),
      findsOneWidget,
    );
  });
}
