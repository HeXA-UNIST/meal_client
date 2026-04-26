import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meal_client/features/announcement/data/announcement_service.dart';
import 'package:meal_client/core/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('checkAnnouncementString', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('저장된 값 없을 때 새 공지 → 공지 반환 후 저장', () async {
      final result = await checkAnnouncementString('새 공지입니다');

      expect(result, '새 공지입니다');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.announcementKey), '새 공지입니다');
    });

    test('기존 공지와 다를 때 → 새 공지 반환 후 저장', () async {
      SharedPreferences.setMockInitialValues(
          {StorageKeys.announcementKey: '이전 공지'});

      final result = await checkAnnouncementString('새 공지입니다');

      expect(result, '새 공지입니다');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StorageKeys.announcementKey), '새 공지입니다');
    });

    test('기존 공지와 동일할 때 → null 반환', () async {
      SharedPreferences.setMockInitialValues(
          {StorageKeys.announcementKey: '기존 공지'});

      final result = await checkAnnouncementString('기존 공지');

      expect(result, isNull);
    });
  });
}
