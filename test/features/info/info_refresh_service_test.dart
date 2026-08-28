import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';

void main() {
  group('InfoRefreshService', () {
    test('refreshInfo는 가져온 raw JSON을 info cache에 저장', () async {
      String? storedRaw;
      final service = InfoRefreshService(
        cache: _memoryInfoCache(onWrite: (rawJson) => storedRaw = rawJson),
        fetchRaw: (_, {ifModifiedSince}) async => _ok(_rawInfoJson()),
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
        fetchRaw: (_, {ifModifiedSince}) async => _ok('[]'),
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
        fetchRaw: (_, {ifModifiedSince}) async => _ok(_rawInfoJson()),
        throwOnCacheWriteFailure: true,
      );

      await expectLater(
        service.refreshInfo(),
        throwsA(isA<InfoCacheWriteException>()),
      );
    });

    test('캐시에 last_modified가 있으면 If-Modified-Since로 되돌려 보낸다', () async {
      String? sentIfModifiedSince;
      var readCount = 0;
      final cache = InfoCache(
        writeFile: (_, _) async {},
        readFile: (_) async {
          readCount++;
          return _rawInfoJson('공지', '2026-08-23T15:00:00.000Z');
        },
        readLastModified: (_) async => DateTime.utc(2026, 8, 23),
      );
      final service = InfoRefreshService(
        cache: cache,
        fetchRaw: (_, {ifModifiedSince}) async {
          sentIfModifiedSince = ifModifiedSince;
          return _ok(_rawInfoJson());
        },
      );

      await service.refreshInfo();

      expect(sentIfModifiedSince, '2026-08-23T15:00:00.000Z');
      expect(readCount, greaterThan(0));
    });

    test('304 응답이면 캐시된 info를 반환하고 다시 쓰지 않는다', () async {
      var writeCount = 0;
      final cache = InfoCache(
        writeFile: (_, _) async => writeCount++,
        readFile: (_) async =>
            _rawInfoJson('캐시된 공지', '2026-08-23T15:00:00.000Z'),
        readLastModified: (_) async => DateTime.utc(2026, 8, 23),
      );
      final service = InfoRefreshService(
        cache: cache,
        fetchRaw: (_, {ifModifiedSince}) async =>
            const (statusCode: 304, body: null),
      );

      final info = await service.refreshInfo();

      expect(info.announcement?.content.ko, '캐시된 공지');
      expect(writeCount, 0);
    });

    test('304인데 캐시 본문이 손상됐으면 조건부 없이 재요청한다', () async {
      final sentHeaders = <String?>[];
      var rawInfo = '{"last_modified":"2026-08-23T15:00:00.000Z"}';
      final cache = InfoCache(
        writeFile: (_, data) async => rawInfo = data,
        readFile: (_) async => rawInfo,
        readLastModified: (_) async => DateTime.utc(2026, 8, 23),
      );
      final service = InfoRefreshService(
        cache: cache,
        fetchRaw: (_, {ifModifiedSince}) async {
          sentHeaders.add(ifModifiedSince);
          return sentHeaders.length == 1
              ? const (statusCode: 304, body: null)
              : _ok(_rawInfoJson('복구된 공지'));
        },
      );

      final info = await service.refreshInfo();

      expect(info.announcement?.content.ko, '복구된 공지');
      expect(sentHeaders, ['2026-08-23T15:00:00.000Z', null]);
      expect(jsonDecode(rawInfo)['announcement']['content']['ko'], '복구된 공지');
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
      final olderResponse = Completer<ConditionalResponse>();
      final newerResponse = Completer<ConditionalResponse>();
      var olderNow = DateTime.utc(2026, 4, 14, 1);
      var newerNow = DateTime.utc(2026, 4, 14, 2);
      final older = InfoRefreshService(
        cache: cache,
        clock: () => olderNow,
        fetchRaw: (_, {ifModifiedSince}) => olderResponse.future,
      ).refreshInfo();
      final newer = InfoRefreshService(
        cache: cache,
        clock: () => newerNow,
        fetchRaw: (_, {ifModifiedSince}) => newerResponse.future,
      ).refreshInfo();

      newerNow = DateTime.utc(2026, 4, 14, 3);
      writeTime = newerNow;
      newerResponse.complete(_ok(_rawInfoJson('최신')));
      await newer;

      olderNow = DateTime.utc(2026, 4, 14, 4);
      writeTime = olderNow;
      olderResponse.complete(_ok(_rawInfoJson('늦은 이전')));
      await older;

      expect(
        AppInfo.fromJson(jsonDecode(rawInfo)).announcement?.content.ko,
        '최신',
      );
    });
  });
}

ConditionalResponse _ok(String body) => (statusCode: 200, body: body);

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

String _rawInfoJson([String notice = 'notice', String? lastModified]) {
  return jsonEncode({
    'last_modified': ?lastModified,
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
