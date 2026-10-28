import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/core/constants.dart';

import 'locale_preferences.dart';

/// 기본 저장소의 언어를 읽는다. iOS의 현재 언어는 initializeAppLocale로 읽는다.
Locale loadAppLocale(SharedPreferences prefs) =>
    Locale(prefs.get(StorageKeys.locale) == 'ko' ? 'ko' : 'en');

/// 시스템 선호 언어 중 먼저 나오는 지원 언어를 사용하고, 없으면 영어를 쓴다.
Locale resolveInitialAppLocale(List<Locale> locales) {
  for (final locale in locales) {
    if (locale.languageCode == 'ko' || locale.languageCode == 'en') {
      return Locale(locale.languageCode);
    }
  }
  return const Locale('en');
}

/// 최초 앱 실행 전에는 시스템 언어를 임시로 사용하며 저장이나 이관은 하지 않는다.
Future<Locale> readAppLocale(
  SharedPreferences prefs, {
  SharedPreferencesAsync? sharedPreferences,
  List<Locale>? platformLocales,
}) async {
  final shared = sharedPreferences ?? await sharedAppLocalePreferences();
  final code = shared == null
      ? prefs.get(StorageKeys.locale)
      : await shared.getString(StorageKeys.locale);
  if (code == null) {
    return resolveInitialAppLocale(
      platformLocales ?? PlatformDispatcher.instance.locales,
    );
  }
  if (code != 'ko' && code != 'en') {
    throw StateError('Saved app locale is missing or invalid');
  }
  return Locale(code as String);
}

/// iOS는 공유 설정을 우선하고 기존 앱 설정을 한 번 이관한다.
/// 저장된 언어가 없을 때만 시스템 선호 언어를 사용한다.
/// 앱 시작은 실패 시 임시 언어를 허용하지만 백그라운드 예약은 오류를 전달한다.
Future<Locale> initializeAppLocale(
  SharedPreferences prefs, {
  List<Locale>? platformLocales,
  SharedPreferencesAsync? sharedPreferences,
  bool allowFallback = false,
}) async {
  final saved = prefs.get(StorageKeys.locale);
  final fallback = saved == 'ko' || saved == 'en'
      ? Locale(saved as String)
      : resolveInitialAppLocale(
          platformLocales ?? PlatformDispatcher.instance.locales,
        );
  SharedPreferencesAsync? shared;
  try {
    shared = sharedPreferences ?? await sharedAppLocalePreferences();
    if (shared != null) {
      final code = await shared.getString(StorageKeys.locale);
      if (code != null && code != 'ko' && code != 'en') {
        throw StateError('Saved app locale is invalid');
      }
      if (code == 'ko' || code == 'en') {
        await _removeLegacyLocale(prefs);
        return Locale(code!);
      }
    }
  } catch (error, stackTrace) {
    if (!allowFallback) rethrow;
    reportAppLocaleError('read', error, stackTrace);
    // 조회 실패는 값이 없다는 뜻이 아니므로 임시 언어를 저장하지 않는다.
    return fallback;
  }
  if (shared == null && saved == fallback.languageCode) return fallback;
  try {
    if (!await saveAppLocale(prefs, fallback, sharedPreferences: shared)) {
      throw StateError('App locale write failed');
    }
  } catch (error, stackTrace) {
    if (!allowFallback) rethrow;
    reportAppLocaleError('write', error, stackTrace);
  }
  return fallback;
}

Future<bool> saveAppLocale(
  SharedPreferences prefs,
  Locale locale, {
  SharedPreferencesAsync? sharedPreferences,
}) async {
  final shared = sharedPreferences ?? await sharedAppLocalePreferences();
  if (shared == null) {
    try {
      final persisted = await prefs.setString(
        StorageKeys.locale,
        locale.languageCode,
      );
      if (!persisted) await _reloadLocalePreferences(prefs);
      return persisted;
    } catch (error) {
      await _reloadLocalePreferences(prefs);
      rethrow;
    }
  }
  // 공유 저장소에 저장한 뒤에만 이관 원본을 지운다. 이후에는 공유 값만 갱신한다.
  await shared.setString(StorageKeys.locale, locale.languageCode);
  await _removeLegacyLocale(prefs);
  return true;
}

Future<void> _removeLegacyLocale(SharedPreferences prefs) async {
  try {
    if (prefs.containsKey(StorageKeys.locale)) {
      if (!await prefs.remove(StorageKeys.locale)) {
        throw StateError('Legacy locale removal failed');
      }
    }
  } catch (error, stackTrace) {
    await _reloadLocalePreferences(prefs);
    // 공유 값은 이미 유효하므로 원본 정리 실패가 언어 적용을 막지 않는다.
    reportAppLocaleError('cleanup', error, stackTrace);
  }
}

Future<void> _reloadLocalePreferences(SharedPreferences prefs) async {
  try {
    // legacy API는 디스크 저장 전에 캐시를 바꾸므로 실패 시 원본으로 복구한다.
    await prefs.reload();
  } catch (error, stackTrace) {
    reportAppLocaleError('reload', error, stackTrace);
  }
}

void reportAppLocaleError(
  String operation,
  Object error,
  StackTrace stackTrace,
) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'BapU app locale',
      context: ErrorDescription('while performing locale $operation'),
    ),
  );
}
