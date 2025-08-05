import 'meal.dart';
import 'storage.dart';
import 'api_v2.dart';

const _fileName = "meal.json";

Future<WeekMeal> fetchAndCacheMealData() async {
  final rawMeal = await fetchRawMeal();
  await saveFileAsString(_fileName, rawMeal);
  return parseRawMeal(rawMeal);
}

Future<WeekMeal> getCachedMealData() async {
  final rawMeal = await readFileAsString(_fileName);
  return parseRawMeal(rawMeal);
}
