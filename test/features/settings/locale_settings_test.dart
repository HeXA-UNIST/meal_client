import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/settings/locale_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('기존 앱 언어를 공유 저장소로 이관한 후 공유 값만 갱신한다', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ko'});
    final prefs = await SharedPreferences.getInstance();
    final shared = _SharedLocalePreferences();
    expect(
      await initializeAppLocale(
        prefs,
        sharedPreferences: shared,
        platformLocales: [const Locale('en')],
      ),
      const Locale('ko'),
    );
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
    expect(shared.values[StorageKeys.locale], 'ko');

    await saveAppLocale(prefs, const Locale('en'), sharedPreferences: shared);
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
    expect(
      await initializeAppLocale(
        prefs,
        sharedPreferences: shared,
        platformLocales: [const Locale('ko')],
      ),
      const Locale('en'),
    );
  });

  test('이미 저장한 공유 언어가 남은 이관 원본과 플랫폼 언어보다 우선한다', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ko'});
    final prefs = await SharedPreferences.getInstance();
    final shared = _SharedLocalePreferences();
    shared.values[StorageKeys.locale] = 'en';
    expect(
      await initializeAppLocale(
        prefs,
        sharedPreferences: shared,
        platformLocales: [const Locale('ko')],
      ),
      const Locale('en'),
    );
    expect(shared.writes, 0);
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
  });

  test('공유 저장소가 비어 있으면 최초 플랫폼 언어를 한 번만 저장한다', () async {
    for (final locales in <List<Locale>>[
      [const Locale('ko', 'KR')],
      [const Locale('ja'), const Locale('ko')],
      [],
    ]) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final shared = _SharedLocalePreferences();
      final expected = locales.isNotEmpty && locales.first.languageCode == 'ko'
          ? const Locale('ko')
          : const Locale('en');
      expect(
        await initializeAppLocale(
          prefs,
          sharedPreferences: shared,
          platformLocales: locales,
        ),
        expected,
      );
      expect(
        await initializeAppLocale(
          prefs,
          sharedPreferences: shared,
          platformLocales: [
            Locale(expected.languageCode == 'ko' ? 'en' : 'ko'),
          ],
        ),
        expected,
      );
      expect(shared.writes, 1);
      expect(prefs.containsKey(StorageKeys.locale), isFalse);
    }
  });

  test('공유 저장 실패 시 이관 원본을 보존하고 다음 시도에서 복구한다', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ko'});
    final prefs = await SharedPreferences.getInstance();
    final shared = _SharedLocalePreferences();
    shared.values['failWrites'] = true;
    await expectLater(
      initializeAppLocale(prefs, sharedPreferences: shared),
      throwsStateError,
    );
    expect(prefs.getString(StorageKeys.locale), 'ko');
    expect(shared.values[StorageKeys.locale], isNull);
    shared.values['failWrites'] = false;
    expect(
      await initializeAppLocale(prefs, sharedPreferences: shared),
      const Locale('ko'),
    );
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
  });

  test('공유 설정 조회 실패 시 최초 언어로 덮어쓰지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final shared = _SharedLocalePreferences();
    shared.values['failReads'] = true;
    await expectLater(
      initializeAppLocale(
        prefs,
        sharedPreferences: shared,
        platformLocales: [const Locale('ko')],
      ),
      throwsStateError,
    );
    expect(shared.writes, 0);
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
  });
}

class _SharedLocalePreferences extends Fake implements SharedPreferencesAsync {
  final values = <String, Object?>{};
  int get writes => values['writes'] as int? ?? 0;

  @override
  Future<String?> getString(String key) async {
    if (values['failReads'] == true) {
      throw StateError('Shared locale read failed');
    }
    return values[key] as String?;
  }

  @override
  Future<void> setString(String key, String value) async {
    if (values['failWrites'] == true) {
      throw StateError('Shared locale write failed');
    }
    values[key] = value;
    values['writes'] = writes + 1;
  }
}
