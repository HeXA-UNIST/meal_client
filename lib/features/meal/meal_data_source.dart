import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';

final _mealCache = MealCache();
final _mealRefreshService = MealRefreshService(cache: _mealCache);
Future<MealResponse>? _foregroundMealRefresh;

typedef RawMealFetcher = Future<String> Function(String url);

typedef MealResponse = ({WeekMeal weekMeal, WeekMeta weekMeta});

Future<MealResponse> fetchAndCacheMealData({
  RawMealFetcher? fetch,
  bool prefetchNextWeek = true,
  bool waitForNextWeekPrefetch = false,
  DateTime? now,
}) async {
  final instant = now ?? DateTime.now();
  final service = fetch == null
      ? _mealRefreshService
      : MealRefreshService(cache: _mealCache, fetchRaw: fetch);
  return service.refreshMealResponse(
    prefetchNextWeek: prefetchNextWeek,
    waitForNextWeekPrefetch: waitForNextWeekPrefetch,
    now: instant,
  );
}

/// Home과 iOS resume이 공유하는 canonical current-week 단일 실행 경로.
Future<MealResponse> fetchAndCacheCanonicalMealData({
  bool waitForNextWeekPrefetch = false,
  DateTime? now,
}) => runForegroundMealRefresh(
  () => fetchAndCacheMealData(
    waitForNextWeekPrefetch: waitForNextWeekPrefetch,
    now: now,
  ),
);

Future<MealResponse> runForegroundMealRefresh(
  Future<MealResponse> Function() refresh,
) async {
  final running = _foregroundMealRefresh;
  if (running != null) return running;
  final operation = refresh();
  _foregroundMealRefresh = operation;
  try {
    return await operation;
  } finally {
    if (identical(_foregroundMealRefresh, operation)) {
      _foregroundMealRefresh = null;
    }
  }
}

Future<MealResponse> getCachedMealData({
  MealCache? cache,
  MealCache? nextWeekCache,
  DateTime? now,
}) async {
  final currentWeekStart = kstWeekStartForInstant(now ?? DateTime.now());
  return _readCachedMealForWeek(
    currentWeekStart,
    cache: cache ?? _mealCache,
    nextWeekCache:
        nextWeekCache ?? MealCache(fileName: StorageKeys.nextMealCacheFile),
  );
}

Future<MealResponse> _readCachedMealForWeek(
  DateTime weekStart, {
  required MealCache cache,
  required MealCache nextWeekCache,
}) async {
  final canonical = await cache.readValidatedMealForWeek(weekStart);
  if (canonical != null) {
    return (weekMeal: canonical.weekMeal, weekMeta: canonical.weekMeta);
  }
  final next = await nextWeekCache.readValidatedMealForWeek(weekStart);
  if (next != null) {
    return (weekMeal: next.weekMeal, weekMeta: next.weekMeta);
  }
  throw Exception('Outdated cache');
}

/// 지정 주 식단을 가져와 next-week cache에 저장한다.
/// 미리보기는 이 한 요청의 결과를 화면 표시와 cache 갱신에 함께 사용한다.
Future<WeekMeal> fetchAndCacheMealDataForWeek(
  String weekStart, {
  RawMealFetcher fetch = fetchRawString,
  MealCache? nextWeekCache,
  NextWeekCacheWriteLock? lockNextWeekCache,
}) {
  return MealRefreshService(
    fetchRaw: fetch,
    nextWeekCache: nextWeekCache,
    lockNextWeekCache: lockNextWeekCache,
  ).refreshAndCacheNextWeekData(weekStart);
}
