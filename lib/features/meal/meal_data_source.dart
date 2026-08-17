import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';

final _mealCache = MealCache();
final _mealRefreshService = MealRefreshService(cache: _mealCache);

typedef RawMealFetcher = Future<String> Function(String url);

typedef MealResponse = ({WeekMeal weekMeal, WeekMeta weekMeta});

Future<MealResponse> fetchAndCacheMealData({
  RawMealFetcher? fetch,
  bool prefetchNextWeek = true,
}) async {
  final service = fetch == null
      ? _mealRefreshService
      : MealRefreshService(cache: _mealCache, fetchRaw: fetch);
  return service.refreshMealResponse(prefetchNextWeek: prefetchNextWeek);
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

/// 지정한 주의 식단을 가져온다. 현재 주 캐시에는 저장하지 않는다.
Future<WeekMeal> fetchMealDataForWeek(
  String weekStart, {
  RawMealFetcher fetch = fetchRawString,
}) async {
  final rawMeal = await fetch(ApiConstants.mealEndpointFor(weekStart));
  return parseRawMeal(rawMeal);
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
