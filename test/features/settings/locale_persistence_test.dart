import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/settings/bapu_settings.dart';
import 'package:meal_client/features/settings/locale_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final throwOnWrite in [false, true]) {
    test(
      '실제 저장 ${throwOnWrite ? '예외' : '실패'} 뒤 캐시와 화면은 저장된 언어를 유지한다',
      () async {
        SharedPreferences.resetStatic();
        final persisted = <String, Object>{
          'flutter.${StorageKeys.locale}': 'en',
        };
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getAll':
            case 'getAllWithParameters':
              return persisted;
            case 'setString':
              if (throwOnWrite) throw PlatformException(code: 'WRITE_FAILED');
              return false;
            default:
              throw StateError('Unexpected preferences method: ${call.method}');
          }
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
          SharedPreferences.resetStatic();
        });
        final prefs = await SharedPreferences.getInstance();
        final settings = BapuSettings(
          prefs,
          notificationPlatform: MealNotificationPlatform.unsupported,
        );
        addTearDown(settings.dispose);
        await expectLater(
          settings.setLocale(const Locale('ko')),
          throwsA(anything),
        );
        expect(settings.locale, const Locale('en'));
        expect(prefs.getString(StorageKeys.locale), 'en');
        expect(await initializeAppLocale(prefs), const Locale('en'));
        expect(persisted['flutter.${StorageKeys.locale}'], 'en');
      },
    );
  }
}
