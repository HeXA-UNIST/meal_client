import 'meal.dart';
import 'storage.dart';
import 'api_v2.dart';

const _fileName = "meal.json";

Future<WeekMeal> fetchAndCacheMealData() async {
  final rawMeal = await fetchRawMeal();
  await saveFileAsString(_fileName, rawMeal);
  return parseRawMeal(rawMeal);
}

int _getKstWeekNumber(DateTime time) {
  final DateTime start;
  {
    final theFirstDay = DateTime.utc(
      time.year,
      1,
      1,
      0,
    ).subtract(Duration(hours: 9)).add(time.timeZoneOffset);
    start = theFirstDay.subtract(Duration(days: theFirstDay.weekday - 1));
  }
  final diff = time.difference(start);
  return (diff.inDays / 7).toInt() + 1;
}

Future<WeekMeal> getCachedMealData() async {
  final fileWeekNum = _getKstWeekNumber(await getLastModifiedOfFile(_fileName));
  final nowWeekNum = _getKstWeekNumber(DateTime.now());
  if (fileWeekNum != nowWeekNum) {
    throw Exception("Outdated cache");
  }

  final rawMeal = await readFileAsString(_fileName);
  return parseRawMeal(rawMeal);
}
