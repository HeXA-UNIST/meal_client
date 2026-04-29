import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/core/storage.dart';
import 'package:meal_client/domain/meal.dart';

Future<WeekMeal> fetchAndCacheMealData() async {
  final rawMeal = await fetchRawString(ApiConstants.mealEndpoint);
  await saveFileAsString(StorageKeys.mealCacheFile, rawMeal);
  return parseRawMeal(rawMeal);
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

Future<WeekMeal> getCachedMealData() async {
  final fileWeekNum = _getKstWeekNumber(
      await getLastModifiedOfFile(StorageKeys.mealCacheFile));
  final nowWeekNum = _getKstWeekNumber(DateTime.now());
  if (fileWeekNum != nowWeekNum) {
    throw Exception("Outdated cache");
  }

  final rawMeal = await readFileAsString(StorageKeys.mealCacheFile);
  return parseRawMeal(rawMeal);
}
