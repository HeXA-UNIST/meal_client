import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/core/network/platform_http_client.dart'
    show createHttpException;
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';

typedef RawStringFetcher = Future<String> Function(String url);
typedef MealCacheWriteLock = Future<void> Function(
  Future<void> Function() action,
);
typedef NextWeekCacheWriteLock = MealCacheWriteLock;

/// 화면 표시와 독립적으로 자동 선반입까지 공유 캐시가 준비됐는지 확인한다.
typedef MealRefreshResult = ({
  WeekMeal weekMeal,
  WeekMeta weekMeta,
  Future<bool> cacheReady,
});

class MealRefreshService {
  MealRefreshService({
    MealCache? cache,
    MealCache? nextWeekCache,
    RawStringFetcher? fetchRaw,
    ConditionalFetcher? fetchConditional,
    DateTime Function()? clock,
    MealCacheWriteLock? lockCanonicalCache,
    NextWeekCacheWriteLock? lockNextWeekCache,
    bool? supportsSharedCache,
    this._throwOnCacheWriteFailure = false,
  }) : _cache = cache ?? MealCache(),
       _nextWeekCache =
           nextWeekCache ?? MealCache(fileName: StorageKeys.nextMealCacheFile),
       _fetchRaw = fetchRaw ?? (kIsWeb ? fetchRawString : null),
       _fetchConditional = fetchConditional ?? fetchRawConditional,
       _clock = clock ?? DateTime.now,
       _lockCanonicalCache =
           lockCanonicalCache ??
           (cache == null
               ? (action) =>
                     withSharedWidgetFileLock(StorageKeys.mealCacheFile, action)
               : (action) => action()),
       _lockNextWeekCache =
           lockNextWeekCache ??
           ((action) =>
               withSharedWidgetFileLock(StorageKeys.nextMealCacheFile, action)),
       _supportsSharedCache = supportsSharedCache ?? supportsSharedWidgetCache;

  final MealCache _cache;
  final MealCache _nextWeekCache;
  final RawStringFetcher? _fetchRaw;
  final ConditionalFetcher _fetchConditional;
  final DateTime Function() _clock;
  final MealCacheWriteLock _lockCanonicalCache;
  final NextWeekCacheWriteLock _lockNextWeekCache;
  final bool _supportsSharedCache;
  final bool _throwOnCacheWriteFailure;

  static Future<void> _nextWeekCacheWriteQueue = Future.value();

  Future<WeekMeal> refreshMealData({
    DateTime? now,
    bool waitForNextWeekPrefetch = false,
  }) async {
    return (await refreshMealResponse(
      now: now,
      waitForNextWeekPrefetch: waitForNextWeekPrefetch,
    )).weekMeal;
  }

  Future<({WeekMeal weekMeal, WeekMeta weekMeta})> refreshMealResponse({
    bool prefetchNextWeek = true,
    bool waitForNextWeekPrefetch = false,
    DateTime? now,
  }) async {
    final result = await refreshMealResponseWithStatus(
      prefetchNextWeek: prefetchNextWeek,
      waitForNextWeekPrefetch: waitForNextWeekPrefetch,
      now: now,
    );
    return (weekMeal: result.weekMeal, weekMeta: result.weekMeta);
  }

  Future<MealRefreshResult> refreshMealResponseWithStatus({
    bool prefetchNextWeek = true,
    bool waitForNextWeekPrefetch = false,
    DateTime? now,
  }) async {
    final requestStartedAt = now ?? _clock();
    final (rawMeal, canonicalWriteSucceeded) = await _refreshCanonicalMeal(
      kstWeekStartForInstant(requestStartedAt),
    );
    final weekMeal = _parseValidRawMeal(rawMeal);
    final weekMeta = parseWeekMeta(rawMeal);
    var cacheReady = Future.value(canonicalWriteSucceeded);
    if (prefetchNextWeek && canonicalWriteSucceeded) {
      final prefetch = _prefetchNextWeekIfEligible(weekMeta, _clock());
      cacheReady = prefetch;
      if (waitForNextWeekPrefetch) {
        await prefetch;
      } else {
        unawaited(prefetch);
      }
    }
    return (weekMeal: weekMeal, weekMeta: weekMeta, cacheReady: cacheReady);
  }

  /// 지정 주 응답을 검증한 뒤 next-week cache에 저장한다.
  Future<WeekMeal> refreshAndCacheNextWeekData(String weekStart) async {
    final response = await _fetchValidatedWeekResponse(weekStart);
    if (!_supportsSharedCache) {
      return response.weekMeal;
    }
    try {
      await _enqueueNextWeekCacheWrite(() async {
        final currentWeekStart = _weekStartOfRevision(
          await _nextWeekCache.readRevision(),
        );
        if (currentWeekStart != null &&
            currentWeekStart.isAfter(response.weekStart)) {
          return;
        }
        await _writeNextWeekRawMealJson(response.rawMeal);
      });
    } catch (e, stackTrace) {
      // 미리보기는 이미 검증한 응답으로 표시할 수 있으므로 cache 저장 실패가
      // 화면 실패로 이어지지 않게 한다.
      debugPrint('[BapU] next-week meal cache write skipped: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
    return response.weekMeal;
  }

  Future<bool> _prefetchNextWeekIfEligible(
    WeekMeta weekMeta,
    DateTime now,
  ) async {
    try {
      if (!_supportsSharedCache) return false;

      final nextWeekStart = weekMeta.nextWeekStart;
      if (nextWeekStart == null) return true;

      final requestedWeekStart = parseWeekStartDate(nextWeekStart);
      final revisionBeforeFetch = await _nextWeekCache.readRevision();
      final hasMatchingWeek = await _nextWeekCache.hasCachedWeek(
        requestedWeekStart,
      );
      final shouldRefresh =
          !hasMatchingWeek ||
          (MealTimeConfig.toKst(now).weekday == DateTime.sunday &&
              !await _nextWeekCache.wasWrittenOnKstSunday(now));
      if (!shouldRefresh) return true;

      final response = await _fetchValidatedWeekResponse(nextWeekStart);
      var written = false;
      await _enqueueNextWeekCacheWrite(() async {
        final revisionAtCommit = await _nextWeekCache.readRevision();
        if (!_sameRevision(revisionBeforeFetch, revisionAtCommit)) {
          final currentWeekStart = _weekStartOfRevision(revisionAtCommit);
          if (currentWeekStart != null &&
              !currentWeekStart.isBefore(requestedWeekStart)) {
            return;
          }
        }
        written = await _writeNextWeekRawMealJson(response.rawMeal);
      });
      return written;
    } catch (e, stackTrace) {
      // 현재 주 canonical cache는 이미 정상 갱신됐으므로 선반입 실패가 이를
      // 무효화하지 않는다. 이후 refresh 또는 미리보기에서 다시 시도한다.
      debugPrint('[BapU] next-week meal prefetch failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<({String rawMeal, WeekMeal weekMeal, DateTime weekStart})>
  _fetchValidatedWeekResponse(String weekStart) async {
    final requestedWeekStart = parseWeekStartDate(weekStart);
    final rawMeal = await _fetchRawMeal(
      ApiConstants.mealEndpointFor(weekStart),
      cache: _nextWeekCache,
      weekStart: requestedWeekStart,
    );
    final weekMeal = _parseValidRawMeal(rawMeal);
    final responseWeekStart = parseWeekMeta(rawMeal).startDate;
    if (!_sameCalendarDate(responseWeekStart, requestedWeekStart)) {
      throw FormatException('Dated meal response belongs to another week');
    }
    return (rawMeal: rawMeal, weekMeal: weekMeal, weekStart: responseWeekStart);
  }

  Future<String> _fetchRawMeal(
    String url, {
    required MealCache cache,
    required DateTime weekStart,
  }) async {
    final cached = _supportsSharedCache
        ? await cache.readValidatedMealForWeek(weekStart)
        : null;
    return (await _fetchRawMealSnapshot(url, cached)).rawMeal;
  }

  Future<({String rawMeal, bool revalidated})> _fetchRawMealSnapshot(
    String url,
    ValidatedMealCache? cached,
  ) async {
    final fetchRaw = _fetchRaw;
    if (fetchRaw != null) {
      return (rawMeal: await fetchRaw(url), revalidated: false);
    }

    final decoded = cached == null ? null : jsonDecode(cached.rawMeal);
    final value = decoded?['etag'];
    final etag = value is String && value.isNotEmpty ? value : null;
    final response = await _fetchConditional(url, ifNoneMatch: etag);
    if (response.statusCode == 304) {
      if (cached != null && etag != null) {
        // 보낸 ETag와 같은 스냅샷을 재사용한다. 다른 isolate가 파일을 바꿔도
        // 304와 무관한 본문을 읽지 않으며, 저장은 기존 잠금과 주차 검증을 거친다.
        // 재검증한 시각도 기록해야 일요일 자동 선반입이 반복되지 않는다.
        debugPrint('[BapU] meal 304 - 캐시 재사용');
        return (rawMeal: cached.rawMeal, revalidated: true);
      }
      // 재사용할 본문이 없으면 조건부 헤더 없이 한 번만 복구를 시도한다.
      final retry = await _fetchConditional(url);
      if (retry.statusCode != 200 || retry.body == null) {
        throw createHttpException(retry.statusCode);
      }
      return (rawMeal: retry.body!, revalidated: false);
    }
    if (response.statusCode != 200 || response.body == null) {
      throw createHttpException(response.statusCode);
    }
    return (rawMeal: response.body!, revalidated: false);
  }

  Future<void> _enqueueNextWeekCacheWrite(Future<void> Function() write) {
    final queued = _nextWeekCacheWriteQueue.then(
      (_) => _lockNextWeekCache(write),
    );
    _nextWeekCacheWriteQueue = queued.then<void>((_) {}, onError: (_, _) {});
    return queued;
  }

  Future<WeekMeal> getFreshOrRefreshMealData({DateTime? now}) async {
    final instant = now ?? DateTime.now();
    final cached = await _cache.readValidatedMealForWeek(
      kstWeekStartForInstant(instant),
    );
    if (cached != null) {
      return cached.weekMeal;
    }

    return refreshMealData(now: now);
  }

  WeekMeal _parseValidRawMeal(String rawMeal) {
    final decoded = jsonDecode(rawMeal);
    // v2 /menu 응답은 최상위가 Map({week, data, ...})이다. 빈 Map이나 배열 등
    // 형식이 어긋난 응답은 캐시에 쓰기 전에 걸러낸다. 구조 검증은 parseRawMeal이 담당.
    if (decoded is! Map || decoded.isEmpty) {
      throw FormatException('Invalid meal API response');
    }

    return parseRawMeal(rawMeal);
  }

  Future<bool> _writeRawMealJson(String rawMeal) async {
    try {
      await _cache.writeRawMealJson(rawMeal);
      return true;
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(e, stackTrace);
      }
      debugPrint('[BapU] meal cache write failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<String?> _readCanonicalRaw() async {
    try {
      return await _cache.readRawMealJson();
    } catch (_) {
      return null;
    }
  }

  ValidatedMealCache? _validatedSnapshot(String? raw, DateTime weekStart) {
    if (!_supportsSharedCache || raw == null) return null;
    try {
      final meta = parseWeekMeta(raw);
      if (!_sameCalendarDate(meta.startDate, weekStart)) return null;
      return (rawMeal: raw, weekMeal: _parseValidRawMeal(raw), weekMeta: meta);
    } catch (_) {
      return null;
    }
  }

  /// 요청 도중 캐시가 바뀌면 새 스냅샷으로 한 번만 재검증한다.
  /// 파일 저장시각은 서버 응답의 선후관계나 최신성을 나타내지 않는다.
  Future<(String, bool)> _refreshCanonicalMeal(DateTime weekStart) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final before = await _readCanonicalRaw();
      final response = await _fetchRawMealSnapshot(
        ApiConstants.mealEndpoint,
        _validatedSnapshot(before, weekStart),
      );
      final raw = response.rawMeal;
      _parseValidRawMeal(raw);
      final committed = await _commitCanonicalMeal(
        raw,
        responseWeekStart: parseWeekMeta(raw).startDate,
        expectedRaw: before,
        revalidated: response.revalidated,
      );
      if (!committed.conflict) return (raw, committed.written);
    }
    final current = _validatedSnapshot(await _readCanonicalRaw(), weekStart);
    if (current == null) throw StateError('Meal cache changed during refresh');
    return (current.rawMeal, false);
  }

  /// 비교와 파일 교체만 기존의 짧은 잠금 안에서 수행한다.
  Future<({bool conflict, bool written})> _commitCanonicalMeal(
    String rawMeal, {
    required DateTime responseWeekStart,
    required String? expectedRaw,
    required bool revalidated,
  }) async {
    var written = false;
    var conflict = false;
    try {
      await _lockCanonicalCache(() async {
        if (_isPastWeek(responseWeekStart, kstWeekStartForInstant(_clock()))) {
          debugPrint('[BapU] discarded meal response from a past KST week');
          return;
        }
        if (await _readCanonicalRaw() != expectedRaw) {
          conflict = true;
          return;
        }
        if (revalidated) {
          // resume의 1시간 갱신 제한은 mtime을 사용한다. 304도 재검증
          // 성공 시각은 반영하되 파일 교체와 본문 쓰기는 생략한다.
          await _cache.markRevalidated(_clock());
          written = true;
        } else {
          written = await _writeRawMealJson(rawMeal);
        }
      });
      return (conflict: conflict, written: written);
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(e, stackTrace);
      }
      debugPrint('[BapU] meal cache commit failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return (conflict: false, written: false);
    }
  }

  Future<bool> _writeNextWeekRawMealJson(String rawMeal) async {
    try {
      await _nextWeekCache.writeRawMealJson(rawMeal);
      return true;
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(e, stackTrace);
      }
      debugPrint('[BapU] next-week meal cache write failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}

bool _sameCalendarDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

bool _isPastWeek(DateTime responseWeekStart, DateTime currentWeekStart) {
  final response = DateTime.utc(
    responseWeekStart.year,
    responseWeekStart.month,
    responseWeekStart.day,
  );
  final current = DateTime.utc(
    currentWeekStart.year,
    currentWeekStart.month,
    currentWeekStart.day,
  );
  return response.isBefore(current);
}

bool _sameRevision(MealCacheRevision? first, MealCacheRevision? second) {
  if (first == null || second == null) return first == null && second == null;
  return first.rawMeal == second.rawMeal &&
      first.updatedAt.isAtSameMomentAs(second.updatedAt);
}

DateTime? _weekStartOfRevision(MealCacheRevision? revision) {
  if (revision == null) return null;
  try {
    return parseWeekMeta(revision.rawMeal).startDate;
  } on FormatException {
    return null;
  }
}
