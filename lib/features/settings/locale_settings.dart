import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/core/constants.dart';

import 'locale_preferences.dart';

/// 기본 저장소의 언어를 읽는다. iOS의 현재 언어는 initializeAppLocale로 읽는다.
Locale loadAppLocale(SharedPreferences prefs) =>
    Locale(prefs.getString(StorageKeys.locale) == 'ko' ? 'ko' : 'en');

/// iOS는 공유 설정을 우선하고 기존 앱 설정을 한 번 이관한다.
/// 저장된 언어가 없을 때만 플랫폼의 첫 언어를 사용한다.
Future<Locale> initializeAppLocale(
  SharedPreferences prefs, {
  List<Locale>? platformLocales,
  SharedPreferencesAsync? sharedPreferences,
}) async {
  final shared = sharedPreferences ?? await sharedAppLocalePreferences();
  if (shared != null) {
    final code = await shared.getString(StorageKeys.locale);
    if (code == 'ko' || code == 'en') {
      // 공유 저장만 성공하고 원본 삭제 전에 종료된 이관도 마무리한다.
      if (prefs.containsKey(StorageKeys.locale)) {
        await prefs.remove(StorageKeys.locale);
      }
      return Locale(code!);
    }
  }
  final saved = prefs.getString(StorageKeys.locale);
  final locales = platformLocales ?? PlatformDispatcher.instance.locales;
  final code = saved == 'ko' || saved == 'en'
      ? saved!
      : locales.isNotEmpty && locales.first.languageCode == 'ko'
      ? 'ko'
      : 'en';
  if (shared == null && saved == code) return Locale(code);
  if (!await saveAppLocale(prefs, Locale(code), sharedPreferences: shared)) {
    throw StateError('App locale write failed');
  }
  return Locale(code);
}

Future<bool> saveAppLocale(
  SharedPreferences prefs,
  Locale locale, {
  SharedPreferencesAsync? sharedPreferences,
}) async {
  final shared = sharedPreferences ?? await sharedAppLocalePreferences();
  if (shared == null) {
    return prefs.setString(StorageKeys.locale, locale.languageCode);
  }
  // 공유 저장소에 저장한 뒤에만 이관 원본을 지운다. 이후에는 공유 값만 갱신한다.
  await shared.setString(StorageKeys.locale, locale.languageCode);
  if (prefs.containsKey(StorageKeys.locale)) {
    await prefs.remove(StorageKeys.locale);
  }
  return true;
}
