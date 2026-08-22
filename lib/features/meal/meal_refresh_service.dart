import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';

typedef RawStringFetcher = Future<String> Function(String url);
typedef MealCacheWriteLock =
    Future<void> Function(Future<void> Function() action);
typedef NextWeekCacheWriteLock = MealCacheWriteLock;

class MealRefreshService {
  MealRefreshService({
    MealCache? cache,
    MealCache? nextWeekCache,
    RawStringFetcher? fetchRaw,
    DateTime Function()? clock,
    MealCacheWriteLock? lockCanonicalCache,
    NextWeekCacheWriteLock? lockNextWeekCache,
    bool? supportsSharedCache,
    bool throwOnCacheWriteFailure = false,
  }) : _cache = cache ?? MealCache(),
       _nextWeekCache =
           nextWeekCache ?? MealCache(fileName: StorageKeys.nextMealCacheFile),
       _fetchRaw = fetchRaw ?? fetchRawString,
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
       _supportsSharedCache = supportsSharedCache ?? supportsSharedWidgetCache,
       _throwOnCacheWriteFailure = throwOnCacheWriteFailure;

  final MealCache _cache;
  final MealCache _nextWeekCache;
  final RawStringFetcher _fetchRaw;
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
    final requestStartedAt = now ?? _clock();
    final rawMeal = await _fetchRaw(ApiConstants.mealEndpoint);
    final weekMeal = _parseValidRawMeal(rawMeal);
    final weekMeta = parseWeekMeta(rawMeal);
    final canonicalWriteSucceeded = await _commitCanonicalMeal(
      rawMeal,
      responseWeekStart: weekMeta.startDate,
      requestStartedAt: requestStartedAt,
    );
    if (prefetchNextWeek && canonicalWriteSucceeded) {
      final prefetch = _prefetchNextWeekIfEligible(weekMeta, _clock());
      if (waitForNextWeekPrefetch) {
        await prefetch;
      } else {
        unawaited(prefetch);
      }
    }
    return (weekMeal: weekMeal, weekMeta: weekMeta);
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

  Future<void> _prefetchNextWeekIfEligible(
    WeekMeta weekMeta,
    DateTime now,
  ) async {
    if (!_supportsSharedCache) return;

    final nextWeekStart = weekMeta.nextWeekStart;
    if (nextWeekStart == null) return;

    final requestedWeekStart = parseWeekStartDate(nextWeekStart);
    final revisionBeforeFetch = await _nextWeekCache.readRevision();
    final hasMatchingWeek = await _nextWeekCache.hasCachedWeek(
      requestedWeekStart,
    );
    final shouldRefresh =
        !hasMatchingWeek ||
        (MealTimeConfig.toKst(now).weekday == DateTime.sunday &&
            !await _nextWeekCache.wasWrittenOnKstSunday(now));
    if (!shouldRefresh) return;

    try {
      final response = await _fetchValidatedWeekResponse(nextWeekStart);
      await _enqueueNextWeekCacheWrite(() async {
        final revisionAtCommit = await _nextWeekCache.readRevision();
        if (!_sameRevision(revisionBeforeFetch, revisionAtCommit)) {
          final currentWeekStart = _weekStartOfRevision(revisionAtCommit);
          if (currentWeekStart != null &&
              !currentWeekStart.isBefore(requestedWeekStart)) {
            return;
          }
        }
        await _writeNextWeekRawMealJson(response.rawMeal);
      });
    } catch (e, stackTrace) {
      // 현재 주 canonical cache는 이미 정상 갱신됐으므로 선반입 실패가 이를
      // 무효화하지 않는다. 이후 refresh 또는 미리보기에서 다시 시도한다.
      debugPrint('[BapU] next-week meal prefetch failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<({String rawMeal, WeekMeal weekMeal, DateTime weekStart})>
  _fetchValidatedWeekResponse(String weekStart) async {
    final requestedWeekStart = parseWeekStartDate(weekStart);
    final rawMeal = await _fetchRaw(ApiConstants.mealEndpointFor(weekStart));
    final weekMeal = _parseValidRawMeal(rawMeal);
    final responseWeekStart = parseWeekMeta(rawMeal).startDate;
    if (!_sameCalendarDate(responseWeekStart, requestedWeekStart)) {
      throw FormatException('Dated meal response belongs to another week');
    }
    return (rawMeal: rawMeal, weekMeal: weekMeal, weekStart: responseWeekStart);
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

  /// 네트워크 완료 순서가 뒤집혀도 먼저 시작한 요청이 최신 cache를 덮지 않게 한다.
  ///
  /// 주차 판정과 수정 시각 비교부터 파일 교체까지만 잠그며, 네트워크 요청과
  /// JSON 파싱은 이 짧은 임계 구역에 포함하지 않는다.
  Future<bool> _commitCanonicalMeal(
    String rawMeal, {
    required DateTime responseWeekStart,
    required DateTime requestStartedAt,
  }) async {
    var written = false;
    try {
      await _lockCanonicalCache(() async {
        if (_isPastWeek(responseWeekStart, kstWeekStartForInstant(_clock()))) {
          debugPrint('[BapU] discarded meal response from a past KST week');
          return;
        }
        try {
          final currentUpdatedAt = await _cache.getRawMealUpdatedAt();
          if (currentUpdatedAt.isAfter(requestStartedAt)) {
            debugPrint('[BapU] discarded stale canonical meal response');
            return;
          }
        } catch (_) {
          // cache가 아직 없거나 timestamp를 읽지 못하면 검증된 응답으로 복구한다.
        }
        written = await _writeRawMealJson(rawMeal);
      });
      return written;
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(e, stackTrace);
      }
      debugPrint('[BapU] meal cache commit failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _writeNextWeekRawMealJson(String rawMeal) async {
    try {
      await _nextWeekCache.writeRawMealJson(rawMeal);
    } catch (e, stackTrace) {
      if (_throwOnCacheWriteFailure) {
        Error.throwWithStackTrace(e, stackTrace);
      }
      debugPrint('[BapU] next-week meal cache write failed: $e');
      debugPrintStack(stackTrace: stackTrace);
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
