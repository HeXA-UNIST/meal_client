import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';

typedef RawStringFetcher = Future<String> Function(String url);

class MealRefreshService {
  MealRefreshService({MealCache? cache, RawStringFetcher? fetchRaw})
    : _cache = cache ?? MealCache(),
      _fetchRaw = fetchRaw ?? fetchRawString;

  final MealCache _cache;
  final RawStringFetcher _fetchRaw;

  Future<WeekMeal> refreshMealData() async {
    final rawMeal = await _fetchRaw(ApiConstants.mealEndpoint);
    await _cache.writeRawMealJson(rawMeal);
    return parseRawMeal(rawMeal);
  }

  Future<WeekMeal> getFreshOrRefreshMealData({DateTime? now}) async {
    if (await _cache.hasFreshMealCache(now ?? DateTime.now())) {
      try {
        final rawMeal = await _cache.readRawMealJson();
        return parseRawMeal(rawMeal);
      } catch (_) {
        return refreshMealData();
      }
    }

    return refreshMealData();
  }
}
