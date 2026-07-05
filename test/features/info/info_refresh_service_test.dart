import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/info/info_cache.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';

void main() {
  group('InfoRefreshService', () {
    test('refreshInfo는 가져온 raw JSON을 info cache에 저장', () async {
      String? storedRaw;
      final service = InfoRefreshService(
        cache: _memoryInfoCache(onWrite: (rawJson) => storedRaw = rawJson),
        fetchRaw: (_) async => _rawInfoJson(),
      );

      final info = await service.refreshInfo();

      expect(storedRaw, _rawInfoJson());
      expect(info.announcement?.content.ko, 'notice');
      expect(info.operatingHours.weekday.cafeterias, isNotEmpty);
    });

    test('refreshInfo는 invalid response를 cache에 저장하지 않음', () async {
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
      'title': {'ko': 'title', 'en': 'Title'},
      'content': {'ko': 'notice', 'en': 'Notice'},
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
