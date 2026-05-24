import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';

final _mealCache = MealCache();
final _mealRefreshService = MealRefreshService(cache: _mealCache);

Future<WeekMeal> fetchAndCacheMealData() async {
  return _mealRefreshService.refreshMealData();
}

Future<WeekMeal> getCachedMealData() async {
  if (!await _mealCache.hasFreshMealCache(DateTime.now())) {
    throw Exception("Outdated cache");
  }

  final rawMeal = await _mealCache.readRawMealJson();
  return parseRawMeal(rawMeal);
}
