import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';

final _mealCache = MealCache();
final _mealRefreshService = MealRefreshService(cache: _mealCache);

typedef RawMealFetcher = Future<String> Function(String url);

typedef MealResponse = ({WeekMeal weekMeal, WeekMeta weekMeta});

Future<MealResponse> fetchAndCacheMealData({RawMealFetcher? fetch}) async {
  final service = fetch == null
      ? _mealRefreshService
      : MealRefreshService(cache: _mealCache, fetchRaw: fetch);
  return service.refreshMealResponse();
}

Future<MealResponse> getCachedMealData() async {
  if (!await _mealCache.hasFreshMealCache(DateTime.now())) {
    throw Exception("Outdated cache");
  }

  final rawMeal = await _mealCache.readRawMealJson();
  return (weekMeal: parseRawMeal(rawMeal), weekMeta: parseWeekMeta(rawMeal));
}

/// 다음 주(또는 임의 주)의 식단을 가져온다. 캐시하지 않는다 — 방문 빈도가 낮은
/// 보조 화면이라 별도 캐시 슬롯을 두지 않기로 했다 (docs/superpowers/specs/
/// 2026-07-07-next-week-preview-design.md 참고).
Future<WeekMeal> fetchNextWeekMealData(
  String date, {
  RawMealFetcher fetch = fetchRawString,
}) async {
  final rawMeal = await fetch(ApiConstants.mealEndpointFor(date));
  return parseRawMeal(rawMeal);
}
