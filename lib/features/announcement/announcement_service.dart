import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_service.dart';

Future<AppAnnouncement?> checkForNewAnnouncement({
  Future<AppInfo> Function() loadInfo = fetchAppInfo,
}) async {
  final info = await loadInfo();
  final announcement = info.announcement;
  if (announcement == null) {
    return null;
  }

  final prefs = await SharedPreferences.getInstance();
  final previous = await getStoredAnnouncement();
  if (announcement.showAnnouncementEveryTime ||
      previous?.contentFingerprint != announcement.contentFingerprint) {
    await prefs.setString(
      StorageKeys.announcementKey,
      jsonEncode(announcement.toJson()),
    );
    return announcement;
  }
  return null;
}

Future<AppAnnouncement?> getStoredAnnouncement() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(StorageKeys.announcementKey);
  if (stored == null) {
    return null;
  }
  return AppAnnouncement.fromStoredString(stored);
}
