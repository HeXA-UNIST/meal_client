import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/info/info_cache.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';

void main() {
  group('InfoRefreshService', () {
    test('refreshInfo는 fetch 결과를 info cache에 raw JSON으로 저장', () async {
      String? storedRaw;
      final service = InfoRefreshService(
        cache: _memoryInfoCache(onWrite: (rawJson) => storedRaw = rawJson),
        fetchRaw: (_) async => _rawInfoJson(),
      );

      final info = await service.refreshInfo();

      expect(storedRaw, _rawInfoJson());
      expect(info.announcement?.content.ko, '공지');
      expect(info.operatingHours.weekday.cafeterias, isNotEmpty);
    });

    test('refreshInfo는 잘못된 응답을 cache에 쓰지 않음', () async {
      String? storedRaw;
      final service = InfoRefreshService(
        cache: _memoryInfoCache(onWrite: (rawJson) => storedRaw = rawJson),
        fetchRaw: (_) async => '[]',
      );

      await expectLater(service.refreshInfo(), throwsFormatException);

      expect(storedRaw, isNull);
    });
  });
}

InfoCache _memoryInfoCache({void Function(String rawJson)? onWrite}) {
  var currentRawJson = '';
  return InfoCache(
    writeFile: (_, data) async {
      currentRawJson = data;
      onWrite?.call(data);
    },
    readFile: (_) async => currentRawJson,
    readLastModified: (_) async => DateTime.utc(2026, 4, 13),
  );
}

String _rawInfoJson() {
  return jsonEncode({
    'announcement': {
      'title': {'ko': '제목', 'en': 'Title'},
      'content': {'ko': '공지', 'en': 'Notice'},
      'showAnnouncementEveryTime': false,
    },
    'operatingHours': {'weekday': _periodJson(), 'weekend': _periodJson()},
  });
}

Map<String, Object> _periodJson() {
  return {
    'dormitory': _cafeteriaJson(),
    'student': _cafeteriaJson(),
    'faculty': _cafeteriaJson(),
  };
}

Map<String, Object> _cafeteriaJson() {
  return {
    'breakfast': {'start': '08:00', 'end': '09:20'},
    'lunch': {'start': '11:30', 'end': '13:30'},
    'dinner': {'start': '17:30', 'end': '19:00'},
  };
}
