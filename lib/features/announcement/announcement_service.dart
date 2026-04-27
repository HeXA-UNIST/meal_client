import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';

Future<String?> checkForNewAnnouncement() async {
  final raw = await fetchRawString(ApiConstants.noticeEndpoint);
  final announcement = (jsonDecode(raw) as Map<String, dynamic>)['content'] as String;

  final prefs = await SharedPreferences.getInstance();
  final prev = prefs.getString(StorageKeys.announcementKey);
  if (announcement != prev) {
    await prefs.setString(StorageKeys.announcementKey, announcement);
    return announcement;
  }
  return null;
}
