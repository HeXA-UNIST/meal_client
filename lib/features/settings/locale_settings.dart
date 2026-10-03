import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/core/constants.dart';

Locale loadAppLocale(SharedPreferences prefs) =>
    Locale(prefs.getString(StorageKeys.locale) == 'ko' ? 'ko' : 'en');

/// 플랫폼 언어는 최초 한 번만 가져오고 이후에는 저장된 앱 언어를 사용한다.
Future<void> initializeAppLocale(
  SharedPreferences prefs, {
  List<Locale>? platformLocales,
}) async {
  final saved = prefs.getString(StorageKeys.locale);
  if (saved == 'ko' || saved == 'en') return;
  final locales = platformLocales ?? PlatformDispatcher.instance.locales;
  final code = locales.isNotEmpty && locales.first.languageCode == 'ko'
      ? 'ko'
      : 'en';
  if (!await prefs.setString(StorageKeys.locale, code)) {
    throw StateError('App locale write failed');
  }
}
