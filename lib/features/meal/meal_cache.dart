import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/widget_shared_storage.dart';

typedef MealCacheWriter = Future<void> Function(String fileName, String data);
typedef MealCacheReader = Future<String> Function(String fileName);
typedef MealCacheLastModifiedReader =
    Future<DateTime> Function(String fileName);

class MealCache {
  MealCache({
    String fileName = StorageKeys.mealCacheFile,
    MealCacheWriter? writeFile,
    MealCacheReader? readFile,
    MealCacheLastModifiedReader? readLastModified,
  }) : _fileName = fileName,
       _writeFile = writeFile ?? saveSharedWidgetFileAsString,
       _readFile = readFile ?? readSharedWidgetFileAsString,
       _readLastModified =
           readLastModified ?? getLastModifiedOfSharedWidgetFile;

  final String _fileName;
  final MealCacheWriter _writeFile;
  final MealCacheReader _readFile;
  final MealCacheLastModifiedReader _readLastModified;

  Future<void> writeRawMealJson(String rawJson) {
    return _writeFile(_fileName, rawJson);
  }

  Future<String> readRawMealJson() {
    return _readFile(_fileName);
  }

  Future<DateTime> getRawMealUpdatedAt() {
    return _readLastModified(_fileName);
  }

  Future<bool> hasFreshMealCache(DateTime now) async {
    try {
      final updatedAt = await getRawMealUpdatedAt();
      return MealTimeConfig.kstWeekId(updatedAt) ==
          MealTimeConfig.kstWeekId(now);
    } catch (e, stackTrace) {
      debugPrint('[BapU] meal cache freshness check failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}
