import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/core/storage.dart';
import 'package:meal_client/domain/meal.dart';

typedef RawMealFetcher = Future<String> Function(String url);

typedef MealResponse = ({WeekMeal weekMeal, WeekMeta weekMeta});

Future<MealResponse> fetchAndCacheMealData({
  RawMealFetcher fetch = fetchRawString,
}) async {
  final rawMeal = await fetch(ApiConstants.mealEndpoint);
  final weekMeal = parseRawMeal(rawMeal);
  final weekMeta = parseWeekMeta(rawMeal);
  await saveFileAsString(StorageKeys.mealCacheFile, rawMeal);
  return (weekMeal: weekMeal, weekMeta: weekMeta);
}

int _getKstWeekNumber(DateTime time) {
  final DateTime start;
  {
    final theFirstDay = DateTime.utc(time.year, 1, 1, 0);
    start = theFirstDay.subtract(Duration(days: theFirstDay.weekday - 1));
  }
  final diff = time.toUtc().add(Duration(hours: 9)).difference(start);
  return (diff.inDays / 7).toInt() + 1;
}

Future<MealResponse> getCachedMealData() async {
  final fileWeekNum = _getKstWeekNumber(
    await getLastModifiedOfFile(StorageKeys.mealCacheFile),
  );
  final nowWeekNum = _getKstWeekNumber(DateTime.now());
  if (fileWeekNum != nowWeekNum) {
    throw Exception("Outdated cache");
  }

  final rawMeal = await readFileAsString(StorageKeys.mealCacheFile);
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
