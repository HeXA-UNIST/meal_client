import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/settings/locale_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('시스템 목록에서 한국어와 영어의 우선순위를 따르고 미지원 언어는 건너뛴다', () {
    final cases = <(List<Locale>, Locale)>[
      ([const Locale('en', 'US'), const Locale('ko')], const Locale('en')),
      (
        [const Locale('ja'), const Locale('ko', 'KR'), const Locale('en')],
        const Locale('ko'),
      ),
      (
        [const Locale('ja'), const Locale('en', 'GB'), const Locale('ko')],
        const Locale('en'),
      ),
      ([const Locale('ko')], const Locale('ko')),
      ([const Locale('ja')], const Locale('en')),
      ([], const Locale('en')),
    ];
    for (final (locales, expected) in cases) {
      expect(resolveInitialAppLocale(locales), expected);
    }
  });

  test('소비자는 언어가 없으면 시스템 언어를 사용하고 두 저장소 모두 변경하지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final shared = _SharedLocalePreferences();
    for (final store in [null, shared]) {
      expect(
        await readAppLocale(
          prefs,
          sharedPreferences: store,
          platformLocales: [const Locale('ja'), const Locale('ko', 'KR')],
        ),
        const Locale('ko'),
      );
      expect(
        await readAppLocale(
          prefs,
          sharedPreferences: store,
          platformLocales: [],
        ),
        const Locale('en'),
      );
    }
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
    expect(shared.values, isEmpty);
  });

  test('소비자는 잘못된 저장값과 공유 저장소 조회 실패를 시스템 언어로 대체하지 않는다', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ja'});
    final prefs = await SharedPreferences.getInstance();
    await expectLater(readAppLocale(prefs), throwsStateError);
    final shared = _SharedLocalePreferences();
    shared.values[StorageKeys.locale] = 'ja';
    await expectLater(
      readAppLocale(prefs, sharedPreferences: shared),
      throwsStateError,
    );
    shared.values[StorageKeys.locale] = 'en';
    expect(
      await readAppLocale(
        prefs,
        sharedPreferences: shared,
        platformLocales: [const Locale('ko')],
      ),
      const Locale('en'),
    );
    shared.values['failReads'] = true;
    await expectLater(
      readAppLocale(prefs, sharedPreferences: shared),
      throwsStateError,
    );
    expect(shared.writes, 0);
  });

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
      final expected = resolveInitialAppLocale(locales);
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

  test('앱 시작 시 공유 조회가 실패하면 임시 언어를 쓰되 저장하지 않는다', () async {
    final errors = _captureLocaleErrors();
    for (final saved in [null, 'en']) {
      SharedPreferences.setMockInitialValues({StorageKeys.locale: ?saved});
      final prefs = await SharedPreferences.getInstance();
      final shared = _SharedLocalePreferences();
      shared.values[StorageKeys.locale] = 'ko';
      shared.values['failReads'] = true;
      expect(
        await initializeAppLocale(
          prefs,
          sharedPreferences: shared,
          platformLocales: [const Locale('ja'), const Locale('ko')],
          allowFallback: true,
        ),
        Locale(saved ?? 'ko'),
      );
      expect(shared.writes, 0);
      expect(shared.values[StorageKeys.locale], 'ko');
      expect(prefs.get(StorageKeys.locale), saved);
    }
    expect(errors, hasLength(2));
    expect(errors.first.exception, isStateError);
    expect(errors.first.stack, isNotNull);
  });

  test('앱 시작 시 저장 실패도 선택한 언어로 실행하고 다음 초기화에서 복구한다', () async {
    final errors = _captureLocaleErrors();
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ko'});
    final prefs = await SharedPreferences.getInstance();
    final shared = _SharedLocalePreferences();
    shared.values['failWrites'] = true;
    expect(
      await initializeAppLocale(
        prefs,
        sharedPreferences: shared,
        allowFallback: true,
      ),
      const Locale('ko'),
    );
    expect(prefs.getString(StorageKeys.locale), 'ko');
    expect(shared.values[StorageKeys.locale], isNull);
    shared.values['failWrites'] = false;
    expect(
      await initializeAppLocale(prefs, sharedPreferences: shared),
      const Locale('ko'),
    );
    expect(shared.values[StorageKeys.locale], 'ko');
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
    expect(errors, hasLength(1));
  });

  test('타입이 잘못된 기본 저장값은 시스템 선호 언어로 초기화한다', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 123});
    final prefs = await SharedPreferences.getInstance();
    expect(
      await initializeAppLocale(prefs, platformLocales: [const Locale('ko')]),
      const Locale('ko'),
    );
    expect(prefs.getString(StorageKeys.locale), 'ko');
  });

  test('공유 언어 저장 뒤 원본 삭제 실패는 적용을 막지 않고 다음에 정리한다', () async {
    final errors = _captureLocaleErrors();
    final prefs = _LegacyLocalePreferences();
    final shared = _SharedLocalePreferences();
    expect(
      await saveAppLocale(prefs, const Locale('en'), sharedPreferences: shared),
      isTrue,
    );
    expect(shared.values[StorageKeys.locale], 'en');
    expect(prefs.containsKey(StorageKeys.locale), isTrue);
    expect(
      await initializeAppLocale(prefs, sharedPreferences: shared),
      const Locale('en'),
    );
    expect(prefs.containsKey(StorageKeys.locale), isFalse);
    expect(errors, hasLength(1));
  });
}

List<FlutterErrorDetails> _captureLocaleErrors() {
  final previous = FlutterError.onError;
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  addTearDown(() => FlutterError.onError = previous);
  return errors;
}

class _LegacyLocalePreferences extends Fake implements SharedPreferences {
  Object? saved = 'ko';
  bool failRemoval = true;

  @override
  Future<void> reload() async {}

  @override
  Object? get(String key) => saved;

  @override
  bool containsKey(String key) => saved != null;

  @override
  Future<bool> remove(String key) async {
    if (failRemoval) {
      failRemoval = false;
      return false;
    }
    saved = null;
    return true;
  }
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
