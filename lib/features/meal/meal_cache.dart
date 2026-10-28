import 'package:flutter/foundation.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/widget_shared_storage.dart';
import 'package:meal_client/domain/meal.dart';

typedef MealCacheWriter = Future<void> Function(String fileName, String data);
typedef MealCacheReader = Future<String> Function(String fileName);
typedef MealCacheLastModifiedReader = Future<DateTime> Function(
  String fileName,
);
typedef MealCacheLastModifiedWriter = Future<void> Function(
  String fileName,
  DateTime at,
);

typedef MealCacheRevision = ({String rawMeal, DateTime updatedAt});
typedef ValidatedMealCache = ({
  String rawMeal,
  WeekMeal weekMeal,
  WeekMeta weekMeta,
});

class MealCache {
  MealCache({
    this._fileName = StorageKeys.mealCacheFile,
    MealCacheWriter? writeFile,
    MealCacheReader? readFile,
    MealCacheLastModifiedReader? readLastModified,
    MealCacheLastModifiedWriter? setLastModified,
  }) : _writeFile = writeFile ?? saveSharedWidgetFileAsString,
       _readFile = readFile ?? readSharedWidgetFileAsString,
       _readLastModified =
           readLastModified ?? getLastModifiedOfSharedWidgetFile,
       _setLastModified = setLastModified ?? setLastModifiedOfSharedWidgetFile;

  final String _fileName;
  final MealCacheWriter _writeFile;
  final MealCacheReader _readFile;
  final MealCacheLastModifiedReader _readLastModified;
  final MealCacheLastModifiedWriter _setLastModified;

  Future<void> writeRawMealJson(String rawJson) {
    return _writeFile(_fileName, rawJson);
  }

  Future<String> readRawMealJson() {
    return _readFile(_fileName);
  }

  Future<DateTime> getRawMealUpdatedAt() {
    return _readLastModified(_fileName);
  }

  /// 현재 본문이 서버에서 재검증된 시각을 파일 메타데이터에 반영한다.
  Future<void> markRevalidated(DateTime at) => _setLastModified(_fileName, at);

  /// [weekStart]에 해당하는 raw 응답인지 payload의 시작일로 판별한다.
  Future<bool> hasCachedWeek(DateTime weekStart) async {
    return (await readValidatedMealForWeek(weekStart)) != null;
  }

  /// 파일을 한 번만 읽어 week identity와 전체 payload를 함께 검증한다.
  /// 검증 성공한 동일 스냅샷과 파싱 결과를 호출자에게 돌려 재파싱을 피한다.
  Future<ValidatedMealCache?> readValidatedMealForWeek(
    DateTime weekStart,
  ) async {
    try {
      final rawMeal = await readRawMealJson();
      final weekMeta = parseWeekMeta(rawMeal);
      final weekMeal = parseRawMeal(rawMeal);
      return _sameCalendarDate(weekMeta.startDate, weekStart)
          ? (rawMeal: rawMeal, weekMeal: weekMeal, weekMeta: weekMeta)
          : null;
    } catch (e, stackTrace) {
      if (isMissingSharedWidgetFileError(e)) {
        return null;
      }
      debugPrint('[BapU] meal cache week check failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  /// 본문과 마지막 저장·재검증 시각. 갱신 제한과 isolate 간 변경 판정에 쓴다.
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
