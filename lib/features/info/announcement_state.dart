import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_data_source.dart';

Future<AppAnnouncement?> checkForNewAnnouncement({
  Future<AppInfo> Function() loadInfo = fetchAppInfo,
}) async {
  final info = await loadInfo();
  final announcement = info.announcement;
  if (announcement == null) {
    return null;
  }

  final previous = await getStoredAnnouncement();
  if (announcement.showAnnouncementEveryTime ||
      previous?.contentFingerprint != announcement.contentFingerprint) {
    return announcement;
  }
  return null;
}

/// 실제 팝업을 표시한 공지만 다음 시작 안내에서 제외한다.
Future<void> saveDisplayedAnnouncement(AppAnnouncement announcement) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    StorageKeys.announcementKey,
    jsonEncode(announcement.toJson()),
  );
}

Future<AppAnnouncement?> getStoredAnnouncement() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(StorageKeys.announcementKey);
  if (stored == null) {
    return null;
  }
  return AppAnnouncement.fromStoredString(stored);
}
