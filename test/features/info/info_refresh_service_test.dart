import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_cache.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';

void main() {
  group('InfoRefreshService', () {
    test('캐시 ETag로 재검증하고 304에서 기존 본문을 반환한다', () async {
      String? storedRaw;
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
      final revalidated = await service.refreshInfoWithStatus();

      expect(sentEtags, [null, '"info-v2"']);
      expect(storedRaw, rawInfo);
      expect(info.announcement?.content.ko, 'notice');
      expect(revalidated.info.announcement?.content.ko, 'notice');
      expect(revalidated.cacheReady, isTrue);
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
    test('저장 실패 시 화면 응답은 보존하되 연기를 막고 strict 모드는 예외를 반환한다', () async {
      for (final strict in [false, true]) {
        final service = InfoRefreshService(
          cache: InfoCache(
            writeFile: (_, _) async => throw Exception('disk full'),
            readFile: (_) async => '',
          ),
          fetchRaw: (_, {ifNoneMatch}) async => _ok(_rawInfoJson()),
          throwOnCacheWriteFailure: strict,
        );
        if (strict) {
          await expectLater(
            service.refreshInfo(),
            throwsA(isA<InfoCacheWriteException>()),
          );
        } else {
          final result = await service.refreshInfoWithStatus();
          expect(result.info.announcement?.content.ko, 'notice');
          expect(result.cacheReady, isFalse);
        }
      }
    });

    test('304인데 캐시 본문이 손상됐으면 조건부 없이 재요청한다', () async {
      final sentHeaders = <String?>[];
      var rawInfo = jsonEncode({'etag': '"info-v1"'});
      final cache = InfoCache(
        writeFile: (_, data) async => rawInfo = data,
        readFile: (_) async => rawInfo,
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

    for (final newerFinishesFirst in [false, true]) {
      test('겹친 안내 요청은 완료 순서 $newerFinishesFirst에서도 같은 스냅샷을 반환한다', () async {
        var stored = _rawInfoJson('기존', '"old"');
        final latest = _rawInfoJson('최신', '"new"');
        final cache = InfoCache(
          readFile: (_) async => stored,
          writeFile: (_, data) async => stored = data,
        );
        final responses = List.generate(
          2,
          (_) => Completer<ConditionalResponse>(),
        );
        final started = List.generate(2, (_) => Completer<void>());
        Future<AppInfo> request(int index) {
          var first = true;
          return InfoRefreshService(
            cache: cache,
            fetchRaw: (_, {ifNoneMatch}) async {
              if (first) {
                first = false;
                started[index].complete();
                return responses[index].future;
              }
              return ifNoneMatch == '"new"'
                  ? (statusCode: 304, body: null)
                  : _ok(latest);
            },
          ).refreshInfo();
        }

        final older = request(0);
        await started[0].future;
        final newer = request(1);
        await started[1].future;
        if (newerFinishesFirst) {
          responses[1].complete(_ok(latest));
          await newer;
          responses[0].complete(_ok(_rawInfoJson('이전 응답')));
        } else {
          responses[0].complete(_ok(_rawInfoJson('이전 응답')));
          await older;
          responses[1].complete(_ok(latest));
        }
        final last = await (newerFinishesFirst ? older : newer);
        expect(stored, latest);
        expect(last.announcement?.content.ko, '최신');
      });
    }
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
