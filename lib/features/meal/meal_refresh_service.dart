import 'dart:convert';

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
    final weekMeal = _parseValidRawMeal(rawMeal);
    await _cache.writeRawMealJson(rawMeal);
    return weekMeal;
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

  WeekMeal _parseValidRawMeal(String rawMeal) {
    final decoded = jsonDecode(rawMeal);
    // v2 /menu 응답은 최상위가 Map({week, data, ...})이다. 빈 Map이나 배열 등
    // 형식이 어긋난 응답은 캐시에 쓰기 전에 걸러낸다. 구조 검증은 parseRawMeal이 담당.
    if (decoded is! Map || decoded.isEmpty) {
      throw FormatException('Invalid meal API response');
    }

    return parseRawMeal(rawMeal);
  }
}
