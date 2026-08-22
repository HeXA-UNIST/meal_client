import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/info/app_info.dart';
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
    test('refreshInfo는 strict 모드에서 cache write 실패를 구분 가능한 예외로 throw', () async {
      final service = InfoRefreshService(
        cache: InfoCache(
          writeFile: (_, _) async => throw Exception('disk full'),
          readFile: (_) async => '',
          readLastModified: (_) async => DateTime.utc(2026, 4, 13),
        ),
        fetchRaw: (_) async => _rawInfoJson(),
        throwOnCacheWriteFailure: true,
      );

      await expectLater(
        service.refreshInfo(),
        throwsA(isA<InfoCacheWriteException>()),
      );
    });

    test('늦게 끝난 이전 요청은 최신 info cache를 덮지 않는다', () async {
      var rawInfo = _rawInfoJson('기존');
      var updatedAt = DateTime.utc(2026, 4, 13);
      var writeTime = updatedAt;
      final cache = InfoCache(
        writeFile: (_, data) async {
          rawInfo = data;
          updatedAt = writeTime;
        },
        readFile: (_) async => rawInfo,
        readLastModified: (_) async => updatedAt,
      );
      final olderResponse = Completer<String>();
      final newerResponse = Completer<String>();
      var olderNow = DateTime.utc(2026, 4, 14, 1);
      var newerNow = DateTime.utc(2026, 4, 14, 2);
      final older = InfoRefreshService(
        cache: cache,
        clock: () => olderNow,
        fetchRaw: (_) => olderResponse.future,
      ).refreshInfo();
      final newer = InfoRefreshService(
        cache: cache,
        clock: () => newerNow,
        fetchRaw: (_) => newerResponse.future,
      ).refreshInfo();

      newerNow = DateTime.utc(2026, 4, 14, 3);
      writeTime = newerNow;
      newerResponse.complete(_rawInfoJson('최신'));
      await newer;

      olderNow = DateTime.utc(2026, 4, 14, 4);
      writeTime = olderNow;
      olderResponse.complete(_rawInfoJson('늦은 이전'));
      await older;

      expect(
        AppInfo.fromJson(jsonDecode(rawInfo)).announcement?.content.ko,
        '최신',
      );
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

String _rawInfoJson([String notice = 'notice']) {
  return jsonEncode({
    'announcement': {
      'title': {'ko': 'title', 'en': 'Title'},
      'content': {'ko': notice, 'en': 'Notice'},
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
