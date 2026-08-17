import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/domain/meal.dart';

typedef MealCacheWriter = Future<void> Function(String fileName, String data);
typedef MealCacheReader = Future<String> Function(String fileName);
typedef MealCacheLastModifiedReader =
    Future<DateTime> Function(String fileName);

typedef MealCacheRevision = ({String rawMeal, DateTime updatedAt});

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

  /// [weekStart]에 해당하는 raw 응답인지 payload의 시작일로 판별한다.
  Future<bool> hasCachedWeek(DateTime weekStart) async {
    return (await readValidatedRawMealJsonForWeek(weekStart)) != null;
  }

  /// 파일을 한 번만 읽어 week identity와 전체 payload를 함께 검증한다.
  /// 검증 성공한 동일 스냅샷을 호출자에게 돌려 TOCTOU 재읽기를 피한다.
  Future<String?> readValidatedRawMealJsonForWeek(DateTime weekStart) async {
    try {
      final rawMeal = await readRawMealJson();
      final cacheWeekStart = parseWeekMeta(rawMeal).startDate;
      parseRawMeal(rawMeal);
      return _sameCalendarDate(cacheWeekStart, weekStart) ? rawMeal : null;
    } catch (e, stackTrace) {
      debugPrint('[BapU] meal cache week check failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  /// 자동 선반입이 시작된 뒤 다른 isolate가 파일을 바꿨는지 판별하는 값.
  Future<MealCacheRevision?> readRevision() async {
    try {
      return (
        rawMeal: await readRawMealJson(),
        updatedAt: await getRawMealUpdatedAt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 파일이 [now]가 속한 KST 일요일에 기록됐는지 확인한다.
  ///
  /// next-week cache의 정체성은 payload이고, 이 값은 일요일 한 번의
  /// 자동 선반입을 억제하는 메타데이터로만 사용한다.
  Future<bool> wasWrittenOnKstSunday(DateTime now) async {
    try {
      final updatedAt = await getRawMealUpdatedAt();
      final updatedKst = MealTimeConfig.toKst(updatedAt);
      final nowKst = MealTimeConfig.toKst(now);
      return nowKst.weekday == DateTime.sunday &&
          _sameCalendarDate(updatedKst, nowKst);
    } catch (e, stackTrace) {
      debugPrint('[BapU] meal cache timestamp check failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> hasFreshMealCache(DateTime now) async {
    return hasCachedWeek(kstWeekStartForInstant(now));
  }
}

/// 실제 시각이 속한 KST 주의 월요일을 날짜 전용 UTC 값으로 반환한다.
DateTime kstWeekStartForInstant(DateTime instant) {
  final kst = MealTimeConfig.toKst(instant);
  final date = DateTime.utc(kst.year, kst.month, kst.day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

bool _sameCalendarDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
