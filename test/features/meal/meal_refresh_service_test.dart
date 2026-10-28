import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';

void main() {
  group('MealRefreshService', () {
    test('304는 본문 재저장 없이 재검증 시각을 갱신한다', () async {
      final files = <String, String>{};
      var writes = 0;
      var now = _testClock();
      var updatedAt = now.subtract(const Duration(hours: 2));
      final headers = <String?>[];
      final rawMeal = _rawMealJson('새 메뉴', etag: '"menu-v2"');
      final service = MealRefreshService(
        cache: MealCache(
          writeFile: (_, data) async {
            files['meal.json'] = data;
            writes++;
            updatedAt = now;
          },
          readFile: (_) async => files['meal.json']!,
          readLastModified: (_) async => updatedAt,
          setLastModified: (_, at) async => updatedAt = at,
        ),
        clock: () => now,
        fetchConditional: (_, {ifNoneMatch}) async {
          headers.add(ifNoneMatch);
          return headers.length == 1
              ? (statusCode: 200, body: rawMeal)
              : (statusCode: 304, body: null);
        },
      );

      await service.refreshMealResponse(prefetchNextWeek: false);
      now = now.add(const Duration(hours: 2));
      final response = await service.refreshMealResponseWithStatus(
        prefetchNextWeek: false,
      );
      expect(await response.cacheReady, isTrue);
      expect(updatedAt, now);
      expect(headers, [null, '"menu-v2"']);
      expect(writes, 1);
      expect(_firstDormitoryBreakfastMenu(response.weekMeal), contains('새 메뉴'));
      expect(files['meal.json'], rawMeal);
    });

    final unusableCaches = <String, String>{
      'ETag 없는 이전 형식': _rawMealJson('기존'),
      '다른 주차': _rawMealJson('이전 주', weekStart: '2026-04-06', etag: '"old"'),
      '손상된 본문': '{"etag":"\\"broken\\"","week":{"startDate":"2026-04-13","isCurrentWeek":true},"data":false}',
    };
    for (final entry in unusableCaches.entries) {
      test('${entry.key}이면 조건부 헤더 없이 전체 응답을 저장한다', () async {
        final files = <String, String>{'meal.json': entry.value};
        final rawMeal = _rawMealJson('복구 메뉴', etag: '"new"');
        final service = MealRefreshService(
          cache: _mapMealCache(files, 'meal.json'),
          clock: _testClock,
          fetchConditional: (_, {ifNoneMatch}) async {
            expect(ifNoneMatch, isNull);
            return (statusCode: 200, body: rawMeal);
          },
        );

        await service.refreshMealResponse(prefetchNextWeek: false);

        expect(files['meal.json'], rawMeal);
      });
    }

    test('지정 주 요청은 next cache의 ETag와 본문을 사용한다', () async {
      final next = _rawMealJson(
        '다음 주',
        weekStart: '2026-04-20',
        etag: '"next"',
      );
      final current = _rawMealJson('이번 주', etag: '"current"');
      final files = <String, String>{
        'meal.json': current,
        'meal-next.json': next,
      };
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        clock: _testClock,
        lockNextWeekCache: _withoutLock,
        fetchConditional: (url, {ifNoneMatch}) async {
          expect(url, endsWith('/2026-04-20'));
          expect(ifNoneMatch, '"next"');
          return (statusCode: 304, body: null);
        },
      );

      final response = await service.refreshAndCacheNextWeekData('2026-04-20');

      expect(_firstDormitoryBreakfastMenu(response), contains('다음 주'));
      expect(files, {'meal.json': current, 'meal-next.json': next});
    });

    test('현재 주가 304여도 누락된 다음 주 식단은 선반입한다', () async {
      final files = <String, String>{
        'meal.json': _rawMealJson(
          '이번 주',
          nextWeekStart: '2026-04-20',
          etag: '"current"',
        ),
      };
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: _testClock,
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _withoutLock,
        fetchConditional: (url, {ifNoneMatch}) async {
          if (url.endsWith('/2026-04-20')) {
            return (
              statusCode: 200,
              body: _rawMealJson(
                '다음 주',
                weekStart: '2026-04-20',
                etag: '"next"',
              ),
            );
          }
          expect(ifNoneMatch, '"current"');
          return (statusCode: 304, body: null);
        },
      );

      await service.refreshMealResponse(
        now: DateTime.utc(2026, 4, 14),
        waitForNextWeekPrefetch: true,
      );

      expect(
        parseWeekMeta(files['meal-next.json']!).startDate,
        DateTime(2026, 4, 20),
      );
    });

    test('foreground 현재 주 응답은 다음 주 선반입을 기다리지 않는다', () async {
      final files = <String, String>{};
      final datedFetchStarted = Completer<void>();
      final datedResponse = Completer<String>();
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: _testClock,
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _withoutLock,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) {
            datedFetchStarted.complete();
            return datedResponse.future;
          }
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      final response = await service.refreshMealResponseWithStatus(
        now: DateTime.utc(2026, 4, 14),
      );

      expect(_firstDormitoryBreakfastMenu(response.weekMeal), contains('이번 주'));
      expect(files['meal.json'], contains('이번 주'));
      await datedFetchStarted.future;
      datedResponse.complete(_rawMealJson('다음 주', weekStart: '2026-04-20'));
      expect(await response.cacheReady, isTrue);
    });

    test('background 대기 모드는 다음 주 선반입 완료까지 기다린다', () async {
      final files = <String, String>{};
      final datedFetchStarted = Completer<void>();
      final datedResponse = Completer<String>();
      var refreshCompleted = false;
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: _testClock,
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _withoutLock,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) {
            datedFetchStarted.complete();
            return datedResponse.future;
          }
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      final refresh = service
          .refreshMealResponse(
            now: DateTime.utc(2026, 4, 14),
            waitForNextWeekPrefetch: true,
          )
          .whenComplete(() => refreshCompleted = true);
      await datedFetchStarted.future;

      expect(refreshCompleted, isFalse);
      datedResponse.complete(_rawMealJson('다음 주', weekStart: '2026-04-20'));
      await refresh;
      expect(refreshCompleted, isTrue);
    });

    test('canonical cache 저장 실패 시 유효한 next cache를 덮어쓰지 않는다', () async {
      final files = <String, String>{
        'meal-next.json': _rawMealJson('월요일 fallback', weekStart: '2026-04-13'),
      };
      var datedFetches = 0;
      final service = MealRefreshService(
        cache: MealCache(
          writeFile: (_, _) async => throw Exception('disk full'),
        ),
        clock: _testClock,
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _withoutLock,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) datedFetches++;
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      final response = await service.refreshMealResponseWithStatus(
        now: DateTime.utc(2026, 4, 14),
        waitForNextWeekPrefetch: true,
      );

      expect(datedFetches, 0);
      expect(await response.cacheReady, isFalse);
      expect(files['meal-next.json'], contains('월요일 fallback'));
    });

    test('다른 주 응답은 next cache에 저장하지 않는다', () async {
      final files = <String, String>{};
      final service = MealRefreshService(
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _withoutLock,
        fetchRaw: (_) async => _rawMealJson('다른 주', weekStart: '2026-04-13'),
      );

      await expectLater(
        service.refreshAndCacheNextWeekData('2026-04-20'),
        throwsFormatException,
      );

      expect(files, isEmpty);
    });

    test('미리보기의 이전 주 응답은 더 새로운 next cache를 되돌리지 않는다', () async {
      final files = <String, String>{
        'meal-next.json': _rawMealJson('새 주', weekStart: '2026-04-27'),
      };
      final service = MealRefreshService(
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _withoutLock,
        fetchRaw: (_) async =>
            _rawMealJson('이전 주 미리보기', weekStart: '2026-04-20'),
      );

      final weekMeal = await service.refreshAndCacheNextWeekData('2026-04-20');

      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('이전 주 미리보기'));
      expect(files['meal-next.json'], contains('새 주'));
      expect(files['meal-next.json'], isNot(contains('이전 주 미리보기')));
    });

    test('공유 cache 미지원 플랫폼의 미리보기는 표시만 하고 저장하지 않는다', () async {
      var writes = 0;
      final service = MealRefreshService(
        supportsSharedCache: false,
        nextWeekCache: MealCache(writeFile: (_, _) async => writes++),
        fetchRaw: (_) async => _rawMealJson('웹 미리보기', weekStart: '2026-04-20'),
      );

      final weekMeal = await service.refreshAndCacheNextWeekData('2026-04-20');

      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('웹 미리보기'));
      expect(writes, 0);
    });

    test('자동 선반입 lock timeout은 cache 저장만 건너뛴다', () async {
      final files = <String, String>{};
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: _testClock,
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _lockTimeout,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) {
            return _rawMealJson('다음 주', weekStart: '2026-04-20');
          }
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      final result = await service.refreshMealResponseWithStatus(
        now: DateTime.utc(2026, 4, 14),
        waitForNextWeekPrefetch: true,
      );

      expect(files.containsKey('meal-next.json'), isFalse);
      expect(await result.cacheReady, isFalse);
    });

    test('미리보기 lock timeout은 검증한 식단 표시를 막지 않는다', () async {
      final files = <String, String>{};
      final service = MealRefreshService(
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _lockTimeout,
        fetchRaw: (_) async => _rawMealJson('다음 주', weekStart: '2026-04-20'),
      );

      final weekMeal = await service.refreshAndCacheNextWeekData('2026-04-20');

      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('다음 주'));
      expect(files.containsKey('meal-next.json'), isFalse);
    });

    test('일요일 요청이 월요일에 끝나면 지난 주 응답을 canonical cache에 쓰지 않는다', () async {
      var now = DateTime.utc(2026, 4, 19, 14, 59);
      final files = <String, String>{};
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: () => now,
        fetchRaw: (_) async {
          now = DateTime.utc(2026, 4, 19, 15);
          return _rawMealJson('일요일 응답');
        },
      );

      await service.refreshMealResponse(
        now: DateTime.utc(2026, 4, 19, 14, 59),
        prefetchNextWeek: false,
      );

      expect(files, isEmpty);
    });

    for (final newerFinishesFirst in [false, true]) {
      for (final olderStatus in [200, 304]) {
        test(
          '겹친 $olderStatus 요청은 완료 순서 $newerFinishesFirst에서도 캐시와 반환값이 일치한다',
          () async {
            final latest = _rawMealJson('최신 응답', etag: '"new"');
            final files = <String, String>{
              'meal.json': _rawMealJson('기존', etag: '"cached"'),
            };
            final cache = _mapMealCache(files, 'meal.json');
            final olderResponse = Completer<ConditionalResponse>();
            final newerResponse = Completer<ConditionalResponse>();
            final olderStarted = Completer<void>();
            final newerStarted = Completer<void>();
            MealRefreshService service(
              Completer<ConditionalResponse> response,
              Completer<void> started,
            ) {
              var first = true;
              return MealRefreshService(
                cache: cache,
                clock: _testClock,
                lockCanonicalCache: _withoutLock,
                fetchConditional: (_, {ifNoneMatch}) async {
                  if (first) {
                    first = false;
                    started.complete();
                    return response.future;
                  }
                  // 충돌 후에는 현재 서버 응답으로 재검증한다.
                  return ifNoneMatch == '"new"'
                      ? (statusCode: 304, body: null)
                      : (statusCode: 200, body: latest);
                },
              );
            }

            final older = service(
              olderResponse,
              olderStarted,
            ).refreshMealResponse(prefetchNextWeek: false);
            await olderStarted.future;
            final newer = service(
              newerResponse,
              newerStarted,
            ).refreshMealResponse(prefetchNextWeek: false);
            await newerStarted.future;
            final old = (
              statusCode: olderStatus,
              body: olderStatus == 304 ? null : _rawMealJson('이전 응답'),
            );
            if (newerFinishesFirst) {
              newerResponse.complete((statusCode: 200, body: latest));
              await newer;
              olderResponse.complete(old);
            } else {
              olderResponse.complete(old);
              await older;
              newerResponse.complete((statusCode: 200, body: latest));
            }
            final last = await (newerFinishesFirst ? older : newer);
            expect(files['meal.json'], latest);
            expect(
              _firstDormitoryBreakfastMenu(last.weekMeal),
              contains('최신 응답'),
            );
          },
        );
      }
    }

    test('평일에는 일치하는 next cache를 다시 선반입하지 않는다', () async {
      final files = <String, String>{
        'meal-next.json': _rawMealJson('기존', weekStart: '2026-04-20'),
      };
      var datedFetches = 0;
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: _testClock,
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) datedFetches++;
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      await service.refreshMealResponse(
        now: DateTime.utc(2026, 4, 14),
        waitForNextWeekPrefetch: true,
      );

      expect(datedFetches, 0);
    });

    test('공유 위젯 cache를 지원하지 않는 플랫폼은 자동 선반입을 하지 않는다', () async {
      var datedFetches = 0;
      final service = MealRefreshService(
        cache: _memoryMealCache(rawJson: _rawMealJson('이전')),
        clock: _testClock,
        supportsSharedCache: false,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) datedFetches++;
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      await service.refreshMealResponse(
        now: DateTime.utc(2026, 4, 14),
        waitForNextWeekPrefetch: true,
      );

      expect(datedFetches, 0);
    });

    test('일요일 304 재검증도 기록하여 같은 날 선반입을 반복하지 않는다', () async {
      final files = <String, String>{
        'meal-next.json': _rawMealJson(
          '이전',
          weekStart: '2026-04-20',
          etag: '"next"',
        ),
      };
      var updatedAt = DateTime.utc(2026, 4, 18, 3);
      var datedFetches = 0;
      final nextCache = MealCache(
        fileName: 'meal-next.json',
        writeFile: (name, data) async {
          files[name] = data;
          updatedAt = DateTime.utc(2026, 4, 19, 3);
        },
        readFile: (name) async => files[name]!,
        readLastModified: (_) async => updatedAt,
      );
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: () => DateTime.utc(2026, 4, 19, 3),
        nextWeekCache: nextCache,
        lockNextWeekCache: _withoutLock,
        fetchConditional: (url, {ifNoneMatch}) async {
          if (url.endsWith('/2026-04-20')) {
            datedFetches++;
            expect(ifNoneMatch, '"next"');
            return (statusCode: 304, body: null);
          }
          return (
            statusCode: 200,
            body: _rawMealJson('이번 주', nextWeekStart: '2026-04-20'),
          );
        },
      );
      final sunday = DateTime.utc(2026, 4, 19, 3);

      await service.refreshMealResponse(
        now: sunday,
        waitForNextWeekPrefetch: true,
      );
      await service.refreshMealResponse(
        now: sunday,
        waitForNextWeekPrefetch: true,
      );

      expect(datedFetches, 1);
    });

    test('일요일 미리보기가 저장한 next cache는 자동 선반입을 충족한다', () async {
      final files = <String, String>{};
      var updatedAt = DateTime.utc(2026, 4, 18);
      final nextCache = MealCache(
        fileName: 'meal-next.json',
        writeFile: (name, data) async {
          files[name] = data;
          updatedAt = DateTime.utc(2026, 4, 19, 3);
        },
        readFile: (name) async => files[name]!,
        readLastModified: (_) async => updatedAt,
      );
      await MealRefreshService(
        nextWeekCache: nextCache,
        lockNextWeekCache: _withoutLock,
        fetchRaw: (_) async => _rawMealJson('미리보기', weekStart: '2026-04-20'),
      ).refreshAndCacheNextWeekData('2026-04-20');

      var datedFetches = 0;
      await MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: () => DateTime.utc(2026, 4, 19, 3),
        nextWeekCache: nextCache,
        lockNextWeekCache: _withoutLock,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) datedFetches++;
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      ).refreshMealResponse(
        now: DateTime.utc(2026, 4, 19, 3),
        waitForNextWeekPrefetch: true,
      );

      expect(datedFetches, 0);
      expect(files['meal-next.json'], contains('미리보기'));
    });

    test('nextWeekStart가 바뀌면 평일에도 새 주를 즉시 선반입한다', () async {
      final files = <String, String>{
        'meal-next.json': _rawMealJson('이전', weekStart: '2026-04-20'),
      };
      var requestedUrl = '';
      final service = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: _testClock,
        nextWeekCache: _mapMealCache(files, 'meal-next.json'),
        lockNextWeekCache: _withoutLock,
        fetchRaw: (url) async {
          requestedUrl = url;
          return url.endsWith('/2026-04-27')
              ? _rawMealJson('새 다음 주', weekStart: '2026-04-27')
              : _rawMealJson('이번 주', nextWeekStart: '2026-04-27');
        },
      );

      await service.refreshMealResponse(
        now: DateTime.utc(2026, 4, 14),
        waitForNextWeekPrefetch: true,
      );

      expect(requestedUrl, endsWith('/2026-04-27'));
      expect(
        parseWeekMeta(files['meal-next.json']!).startDate,
        DateTime(2026, 4, 27),
      );
    });

    test('월요일 preview가 쓴 next cache는 일요일 자동 선반입이 덮어쓰지 않는다', () async {
      final files = <String, String>{};
      var updatedAt = DateTime.utc(2026, 4, 18);
      var previewWriteAt = DateTime.utc(2026, 4, 19, 15);
      final nextCache = MealCache(
        fileName: 'meal-next.json',
        writeFile: (name, data) async {
          files[name] = data;
          updatedAt = previewWriteAt;
        },
        readFile: (name) async => files[name]!,
        readLastModified: (_) async => updatedAt,
      );
      final autoDatedResponse = Completer<String>();
      final datedFetchStarted = Completer<void>();
      final automatic = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: () => DateTime.utc(2026, 4, 19, 3),
        nextWeekCache: nextCache,
        lockNextWeekCache: _withoutLock,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) {
            datedFetchStarted.complete();
            return autoDatedResponse.future;
          }
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      final automaticFuture = automatic.refreshMealResponse(
        now: DateTime.utc(2026, 4, 19, 3),
        waitForNextWeekPrefetch: true,
      );
      await datedFetchStarted.future;
      await MealRefreshService(
        nextWeekCache: nextCache,
        lockNextWeekCache: _withoutLock,
        fetchRaw: (_) async => _rawMealJson('preview', weekStart: '2026-04-20'),
      ).refreshAndCacheNextWeekData('2026-04-20');
      autoDatedResponse.complete(
        _rawMealJson('automatic', weekStart: '2026-04-20'),
      );
      await automaticFuture;

      expect(files['meal-next.json'], contains('preview'));
    });

    test('월요일에 nextWeekStart가 바뀌면 늦은 일요일 자동 응답을 버린다', () async {
      final files = <String, String>{};
      var updatedAt = DateTime.utc(2026, 4, 18);
      final nextCache = MealCache(
        fileName: 'meal-next.json',
        writeFile: (name, data) async {
          files[name] = data;
          updatedAt = DateTime.utc(2026, 4, 19, 15);
        },
        readFile: (name) async => files[name]!,
        readLastModified: (_) async => updatedAt,
      );
      final autoResponse = Completer<String>();
      final autoStarted = Completer<void>();
      final automatic = MealRefreshService(
        cache: _mapMealCache(files, 'meal.json'),
        clock: () => DateTime.utc(2026, 4, 19, 3),
        nextWeekCache: nextCache,
        lockNextWeekCache: _withoutLock,
        fetchRaw: (url) async {
          if (url.endsWith('/2026-04-20')) {
            autoStarted.complete();
            return autoResponse.future;
          }
          return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
        },
      );

      final automaticFuture = automatic.refreshMealResponse(
        now: DateTime.utc(2026, 4, 19, 3),
        waitForNextWeekPrefetch: true,
      );
      await autoStarted.future;
      await MealRefreshService(
        nextWeekCache: nextCache,
        lockNextWeekCache: _withoutLock,
        fetchRaw: (_) async => _rawMealJson('new', weekStart: '2026-04-27'),
      ).refreshAndCacheNextWeekData('2026-04-27');
      autoResponse.complete(_rawMealJson('old', weekStart: '2026-04-20'));
      await automaticFuture;

      expect(
        parseWeekMeta(files['meal-next.json']!).startDate,
        DateTime(2026, 4, 27),
      );
    });

    test('동시에 시작한 자동 선반입은 같은 주에 먼저 저장한 응답을 유지한다', () async {
      final files = <String, String>{};
      var updatedAt = DateTime.utc(2026, 4, 18);
      final nextCache = MealCache(
        fileName: 'meal-next.json',
        writeFile: (name, data) async {
          files[name] = data;
          updatedAt = DateTime.utc(2026, 4, 19, 3);
        },
        readFile: (name) async => files[name]!,
        readLastModified: (_) async => updatedAt,
      );
      final firstResponse = Completer<String>();
      final secondResponse = Completer<String>();
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      MealRefreshService automatic(
        Completer<String> response,
        Completer<void> started,
      ) {
        return MealRefreshService(
          cache: _mapMealCache(files, 'meal.json'),
          clock: () => DateTime.utc(2026, 4, 19, 3),
          nextWeekCache: nextCache,
          lockNextWeekCache: _withoutLock,
          fetchRaw: (url) async {
            if (url.endsWith('/2026-04-20')) {
              started.complete();
              return response.future;
            }
            return _rawMealJson('이번 주', nextWeekStart: '2026-04-20');
          },
        );
      }

      final first = automatic(firstResponse, firstStarted).refreshMealResponse(
        now: DateTime.utc(2026, 4, 19, 3),
        waitForNextWeekPrefetch: true,
      );
      final second = automatic(secondResponse, secondStarted)
          .refreshMealResponse(
            now: DateTime.utc(2026, 4, 19, 3),
            waitForNextWeekPrefetch: true,
          );
      await Future.wait([firstStarted.future, secondStarted.future]);
      secondResponse.complete(_rawMealJson('두 번째', weekStart: '2026-04-20'));
      await second;
      firstResponse.complete(_rawMealJson('첫 번째', weekStart: '2026-04-20'));
      await first;

      expect(files['meal-next.json'], contains('두 번째'));
    });

    test('동시에 시작한 자동 선반입은 더 새로운 주를 이전 주 응답으로 되돌리지 않는다', () async {
      final files = <String, String>{};
      var updatedAt = DateTime.utc(2026, 4, 18);
      final nextCache = MealCache(
        fileName: 'meal-next.json',
        writeFile: (name, data) async {
          files[name] = data;
          updatedAt = DateTime.utc(2026, 4, 19, 3);
        },
        readFile: (name) async => files[name]!,
        readLastModified: (_) async => updatedAt,
      );
      final olderResponse = Completer<String>();
      final newerResponse = Completer<String>();
      final olderStarted = Completer<void>();
      final newerStarted = Completer<void>();
      MealRefreshService automatic(
        String nextWeekStart,
        Completer<String> response,
        Completer<void> started,
      ) {
        return MealRefreshService(
          cache: _mapMealCache(files, 'meal.json'),
          clock: () => DateTime.utc(2026, 4, 19, 3),
          nextWeekCache: nextCache,
          lockNextWeekCache: _withoutLock,
          fetchRaw: (url) async {
            if (url.endsWith('/$nextWeekStart')) {
              started.complete();
              return response.future;
            }
            return _rawMealJson('이번 주', nextWeekStart: nextWeekStart);
          },
        );
      }

      final older = automatic('2026-04-20', olderResponse, olderStarted)
          .refreshMealResponse(
            now: DateTime.utc(2026, 4, 19, 3),
            waitForNextWeekPrefetch: true,
          );
      final newer = automatic('2026-04-27', newerResponse, newerStarted)
          .refreshMealResponse(
            now: DateTime.utc(2026, 4, 19, 3),
            waitForNextWeekPrefetch: true,
          );
      await Future.wait([olderStarted.future, newerStarted.future]);
      newerResponse.complete(_rawMealJson('새 주', weekStart: '2026-04-27'));
      await newer;
      olderResponse.complete(_rawMealJson('이전 주', weekStart: '2026-04-20'));
      await older;

      expect(
        parseWeekMeta(files['meal-next.json']!).startDate,
        DateTime(2026, 4, 27),
      );
    });

    test('refreshMealData는 JSON 객체 응답을 캐시에 쓰지 않음', () async {
      String? storedRaw;
      final cache = _memoryMealCache(
        rawJson: _rawMealJson('이전 메뉴'),
        onWrite: (rawJson) => storedRaw = rawJson,
      );
      final service = MealRefreshService(
        cache: cache,
        clock: _testClock,
        fetchRaw: (_) async => '{"error":"temporary"}',
      );

      await expectLater(service.refreshMealData(), throwsFormatException);

      expect(storedRaw, isNull);
    });

    test('refreshMealData는 빈 배열 응답을 캐시에 쓰지 않음', () async {
      String? storedRaw;
      final cache = _memoryMealCache(
        rawJson: _rawMealJson('이전 메뉴'),
        onWrite: (rawJson) => storedRaw = rawJson,
      );
      final service = MealRefreshService(
        cache: cache,
        clock: _testClock,
        fetchRaw: (_) async => '[]',
      );

      await expectLater(service.refreshMealData(), throwsFormatException);

      expect(storedRaw, isNull);
    });
    test('refreshMealData는 기본적으로 캐시 쓰기 실패를 무시', () async {
      final service = MealRefreshService(
        cache: MealCache(
          writeFile: (_, _) async => throw Exception('disk full'),
          readFile: (_) async => _rawMealJson('이전 메뉴'),
        ),
        clock: _testClock,
        fetchRaw: (_) async => _rawMealJson('다운로드 메뉴'),
      );

      final weekMeal = await service.refreshMealData();

      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('다운로드 메뉴'));
    });

    test('refreshMealData는 background strict 모드에서 캐시 쓰기 실패를 throw', () async {
      final service = MealRefreshService(
        cache: MealCache(
          writeFile: (_, _) async => throw Exception('disk full'),
          readFile: (_) async => _rawMealJson('이전 메뉴'),
        ),
        clock: _testClock,
        fetchRaw: (_) async => _rawMealJson('다운로드 메뉴'),
        throwOnCacheWriteFailure: true,
      );

      await expectLater(service.refreshMealData(), throwsException);
    });
  });
}

MealCache _memoryMealCache({
  required String rawJson,
  void Function(String rawJson)? onWrite,
}) {
  var currentRawJson = rawJson;
  return MealCache(
    writeFile: (_, data) async {
      currentRawJson = data;
      onWrite?.call(data);
    },
    readFile: (_) async => currentRawJson,
    setLastModified: (_, _) async {},
  );
}

String _rawMealJson(
  String menu, {
  String weekStart = '2026-04-13',
  String? nextWeekStart,
  String? etag,
}) {
  return jsonEncode({
    'etag': ?etag,
    'week': {
      'startDate': weekStart,
      'isCurrentWeek': true,
      'nextWeekStart': nextWeekStart,
    },
    'lastUpdated': '2026-04-13T09:00:00+09:00',
    'data': [
      {
        'cafeteria': 'DORMITORY',
        'meals': [
          {
            'date': '2026-04-13',
            'dayOfWeek': 'MON',
            'timeType': 'BREAKFAST',
            'menusByType': [
              {
                'menuType': 'KOREAN',
                'sections': [
                  {
                    'sectionType': 'REGULAR',
                    'sectionTitle': null,
                    'calorie': 500,
                    'sectionAllergens': null,
                    'menus': [
                      {'ko': menu, 'en': null, 'allergens': null},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  });
}

MealCache _mapMealCache(Map<String, String> files, String fileName) =>
    MealCache(
      fileName: fileName,
      writeFile: (name, data) async => files[name] = data,
      readFile: (name) async => files[name]!,
      readLastModified: (_) async => DateTime.utc(2026, 4, 14),
      setLastModified: (_, _) async {},
    );

/// 정책 판정만 검증하므로 실제 파일 marker lock은 의도적으로 우회한다.
Future<void> _withoutLock(Future<void> Function() action) => action();

Future<void> _lockTimeout(Future<void> Function() _) async {
  throw TimeoutException('locked');
}

DateTime _testClock() => DateTime.utc(2026, 4, 14);

List<String> _firstDormitoryBreakfastMenu(WeekMeal weekMeal) {
  return weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory].first
      .localizedMenu('ko');
}
