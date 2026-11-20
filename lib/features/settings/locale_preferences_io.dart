import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

Future<SharedPreferencesAsync?> sharedAppLocalePreferences() async {
  if (!Platform.isIOS) return null;
  final group = await const MethodChannel(
    'pro.hexa.meal.meal_client/widget_shared_storage',
  ).invokeMethod<String>('appGroupIdentifier');
  if (group == null || group.isEmpty) {
    throw StateError('iOS App Group identifier is not available');
  }
  return SharedPreferencesAsync(
    options: SharedPreferencesAsyncFoundationOptions(suiteName: group),
  );
}
