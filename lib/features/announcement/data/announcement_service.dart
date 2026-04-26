import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/features/announcement/data/announcement_api.dart';
import 'package:meal_client/core/constants.dart';

/// 주어진 공지 문자열을 저장된 이전 공지와 비교한다.
/// 새 공지이면 저장 후 반환, 동일하면 null 반환.
///
/// [announcement]는 이미 파싱된 공지 문자열이어야 한다.
/// 네트워크 없이 SharedPreferences만 사용하므로 단위 테스트 가능.
Future<String?> checkAnnouncementString(String announcement) async {
  final prefs = await SharedPreferences.getInstance();
  final prev = prefs.getString(StorageKeys.announcementKey);
  if (announcement != prev) {
    await prefs.setString(StorageKeys.announcementKey, announcement);
    return announcement;
  }
  return null;
}

/// 서버에서 공지사항을 가져와 이전 공지와 비교한다.
/// 새 공지가 있으면 저장 후 반환, 동일하면 null 반환.
/// 네트워크 오류, JSON 파싱 오류, 저장 실패 시 예외를 throw한다 (호출부에서 무시 가능).
/// 이 함수는 HTTP 클라이언트 싱글톤에 의존하므로 통합 테스트 수준에서만 검증 가능.
/// 비즈니스 로직(비교·저장)의 단위 테스트는 [checkAnnouncementString]을 사용할 것.
Future<String?> checkForNewAnnouncement() async {
  final rawAnnouncement = await fetchRawAnnouncement();
  final announcement = parseRawAnnouncement(rawAnnouncement);
  return checkAnnouncementString(announcement);
}
