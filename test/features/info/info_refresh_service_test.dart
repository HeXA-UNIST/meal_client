import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';

void main() {
  group('InfoRefreshService', () {
    test('기존 캐시를 갱신한 뒤 ETag로 재검증하고 304에서는 저장 없이 재사용한다', () async {
      String? storedRaw;
      var writeCount = 0;
      final sentEtags = <String?>[];
      final rawInfo = _rawInfoJson('notice', '"info-v2"');
      final service = InfoRefreshService(
        cache: _memoryInfoCache(
          rawJson: jsonEncode({
            ...jsonDecode(_rawInfoJson()) as Map<String, dynamic>,
            'last_modified': 'Thu, 15 Oct 2026 01:21:22 GMT',
          }),
          onWrite: (rawJson) {
            storedRaw = rawJson;
            writeCount++;
          },
        ),
        fetchRaw: (_, {ifNoneMatch}) async {
          sentEtags.add(ifNoneMatch);
          return ifNoneMatch == null
              ? _ok(rawInfo)
              : (statusCode: 304, body: null);
        },
      );

      final info = await service.refreshInfo();
      final revalidated = await service.refreshInfo();

      expect(sentEtags, [null, '"info-v2"']);
      expect(storedRaw, rawInfo);
      expect(writeCount, 1);
      expect(info.announcement?.content.ko, 'notice');
      expect(revalidated.announcement?.content.ko, 'notice');
    });

    test('refreshInfo는 invalid response를 cache에 저장하지 않음', () async {
      String? storedRaw;
      final service = InfoRefreshService(
        cache: _memoryInfoCache(onWrite: (rawJson) => storedRaw = rawJson),
        fetchRaw: (_, {ifNoneMatch}) async => _ok('[]'),
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
        fetchRaw: (_, {ifNoneMatch}) async => _ok(_rawInfoJson()),
        throwOnCacheWriteFailure: true,
      );

      await expectLater(
        service.refreshInfo(),
        throwsA(isA<InfoCacheWriteException>()),
      );
    });

    test('304인데 캐시 본문이 손상됐으면 조건부 없이 재요청한다', () async {
      final sentHeaders = <String?>[];
      var rawInfo = jsonEncode({'etag': '"info-v1"'});
      final cache = InfoCache(
        writeFile: (_, data) async => rawInfo = data,
        readFile: (_) async => rawInfo,
        readLastModified: (_) async => DateTime.utc(2026, 8, 23),
      );
      final service = InfoRefreshService(
        cache: cache,
        fetchRaw: (_, {ifNoneMatch}) async {
          sentHeaders.add(ifNoneMatch);
          return sentHeaders.length == 1
              ? const (statusCode: 304, body: null)
              : _ok(_rawInfoJson('복구된 공지'));
        },
      );

      final info = await service.refreshInfo();

      expect(info.announcement?.content.ko, '복구된 공지');
      expect(sentHeaders, ['"info-v1"', null]);
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
        fetchRaw: (_, {ifNoneMatch}) => olderResponse.future,
      ).refreshInfo();
      final newer = InfoRefreshService(
        cache: cache,
        clock: () => newerNow,
        fetchRaw: (_, {ifNoneMatch}) => newerResponse.future,
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

InfoCache _memoryInfoCache({
  String rawJson = '',
  void Function(String rawJson)? onWrite,
}) {
  var currentRawJson = rawJson;
  return InfoCache(
    writeFile: (_, data) async {
      currentRawJson = data;
      onWrite?.call(data);
    },
    readFile: (_) async => currentRawJson,
    readLastModified: (_) async => DateTime.utc(2026, 4, 13),
  );
}

String _rawInfoJson([String notice = 'notice', String? etag]) {
  return jsonEncode({
    'etag': ?etag,
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
