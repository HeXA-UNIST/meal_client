import 'dart:ui';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';
import 'meal_alert_period.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';

typedef BackgroundCacheRefresh = Future<void> Function();

/// 디버그 빌드에서 UI의 테스트 버튼이 호출하는 함수.
/// 백그라운드 태스크와 동일한 로직을 메인 isolate에서 즉시 실행한다.
/// [keywordsOverride]를 전달하면 SharedPreferences 값 대신 그 키워드 리스트로
/// 검사한다. (UI에서 막 입력한 값이 prefs에 아직 안 들어간 경우 활용)
Future<void> testMealKeywordCheck({
  List<String>? keywordsOverride,
  MealAlertPeriod period = MealAlertPeriod.lunch,
}) => _runMealKeywordCheck(period: period, keywordsOverride: keywordsOverride);

/// Workmanager 백그라운드 격리체(isolate) 진입점.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    if (taskName == mealRefreshTaskName ||
        taskName == Workmanager.iOSBackgroundTask) {
      return refreshBackgroundMealAndInfoCaches();
    }

    final period = periodFromTaskName(taskName);
    if (period != null) {
      try {
        await _runMealKeywordCheck(period: period);
        // 다음날 같은 시각으로 이 시간대 태스크를 다시 등록
        await _rescheduleForNextDay(period);
      } catch (e, stackTrace) {
        debugPrint('[BapU] keyword notification worker failed: $e');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }
    }
    return true;
  });
}

Future<bool> refreshBackgroundMealAndInfoCaches({
  BackgroundCacheRefresh? refreshMealCache,
  BackgroundCacheRefresh? refreshInfoCache,
}) async {
  final mealRefresh =
      refreshMealCache ??
      () async {
        await MealRefreshService(
          throwOnCacheWriteFailure: true,
        ).refreshMealData();
      };
  final infoRefresh =
      refreshInfoCache ??
      () async {
        await InfoRefreshService(throwOnCacheWriteFailure: true).refreshInfo();
      };

  final failures = await Future.wait([
    _captureBackgroundRefreshFailure('meal', mealRefresh),
    _captureBackgroundRefreshFailure('info', infoRefresh),
  ]);

  final mealFailure = failures[0];
  if (mealFailure != null) {
    _logBackgroundRefreshFailure('background meal refresh failed', mealFailure);
    return false;
  }

  final infoFailure = failures[1];
  if (infoFailure != null) {
    if (infoFailure.error is InfoCacheWriteException) {
      _logBackgroundRefreshFailure(
        'background info cache write failed',
        infoFailure,
      );
      return false;
    }

    // develop-widget 병합 시에도 notification 브랜치의 기준은 유지한다.
    // meal cache 갱신이 끝난 뒤 /v2/info fetch/parse 실패만으로는 키워드 알림용
    // background task를 실패시키지 않는다. 공유 cache write 실패만 strict 처리한다.
    _logBackgroundRefreshFailure(
      'background info refresh skipped',
      infoFailure,
    );
  }

  return true;
}

Future<_BackgroundRefreshFailure?> _captureBackgroundRefreshFailure(
  String label,
  BackgroundCacheRefresh refresh,
) async {
  try {
    await refresh();
    return null;
  } catch (e, stackTrace) {
    return _BackgroundRefreshFailure(label, e, stackTrace);
  }
}

void _logBackgroundRefreshFailure(
  String message,
  _BackgroundRefreshFailure failure,
) {
  debugPrint('[BapU] $message (${failure.label}): ${failure.error}');
  debugPrintStack(stackTrace: failure.stackTrace);
}

class _BackgroundRefreshFailure {
  const _BackgroundRefreshFailure(this.label, this.error, this.stackTrace);

  final String label;
  final Object error;
  final StackTrace stackTrace;
}

Future<void> _rescheduleForNextDay(MealAlertPeriod period) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(StorageKeys.notificationEnabled) ?? false;
  if (!enabled) return;

  final key = '${StorageKeys.notificationPeriodTimePrefix}${period.name}';
  final stored = prefs.getString(key);
  if (stored == null) return; // 이 시간대가 꺼졌으면 재등록 안 함

  final parts = stored.split(':');
  if (parts.length < 2) return;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return;

  assert(() {
    debugPrint(
      '[BapU] worker: rescheduling ${period.name} for next day at $hour:$minute',
    );
    return true;
  }());
  await scheduleKeywordNotificationFor(
    period,
    TimeOfDay(hour: hour, minute: minute),
  );
  assert(() {
    debugPrint('[BapU] worker: reschedule call completed');
    return true;
  }());
}

Future<void> _runMealKeywordCheck({
  required MealAlertPeriod period,
  List<String>? keywordsOverride,
}) async {
  final prefs = await SharedPreferences.getInstance();

  final enabled = prefs.getBool(StorageKeys.notificationEnabled) ?? false;
  if (!enabled) return;

  // 키워드 로드 (override 또는 prefs). 공백 제거 + 빈 항목 제외.
  final rawKeywords =
      keywordsOverride ??
      prefs.getStringList(StorageKeys.notificationKeywords) ??
      const <String>[];
  final keywords = rawKeywords
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty)
      .toList(growable: false);
  if (keywords.isEmpty) return;

  final cafeteriaNames =
      prefs.getStringList(StorageKeys.notificationCafeterias) ??
      [Cafeteria.dormitory.name];
  final cafeteriaMap = Cafeteria.values.asNameMap();
  final cafeterias = {
    for (final n in cafeteriaNames)
      if (cafeteriaMap[n] != null) cafeteriaMap[n]!,
  };
  if (cafeterias.isEmpty) return;

  final WeekMeal weekMeal;
  try {
    weekMeal = await MealRefreshService().getFreshOrRefreshMealData();
  } catch (_) {
    return;
  }

  // 이 시간대가 검사할 요일(오늘 또는 내일)
  final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final targetDate = period.tomorrow
      ? kstNow.add(const Duration(days: 1))
      : kstNow;
  final targetDay = DayOfWeek.values[targetDate.weekday - 1];
  final mealOfDay = period.mealOfDay;

  // 키워드별 매칭 결과: { "떡갈비" -> ["기숙사 한식"], "국" -> [...] }
  final matchesByKeyword = <String, List<String>>{};
  for (final keyword in keywords) {
    final keywordLower = keyword.toLowerCase();
    final matches = <String>[];

    for (final cafeteria in cafeterias) {
      final meals = weekMeal[targetDay][mealOfDay][cafeteria];

      if (cafeteria == Cafeteria.dormitory) {
        // 기숙사는 한식·할랄을 각각 구분해 표시
        final seen = <String>{};
        for (final meal in meals) {
          if (!meal.menu.any(
            (item) =>
                item.ko.toLowerCase().contains(keywordLower) ||
                (item.en?.toLowerCase().contains(keywordLower) ?? false),
          )) {
            continue;
          }
          final typeLabel = switch (meal) {
            KoreanMeal _ => ' 한식',
            HalalMeal _ => ' 할랄',
            _ => '',
          };
          final label = '기숙사$typeLabel';
          if (seen.add(label)) matches.add(label);
        }
      } else {
        final cafeteriaLabel = switch (cafeteria) {
          Cafeteria.dormitory => '기숙사', // unreachable
          Cafeteria.student => '학생',
          Cafeteria.faculty => '교직원',
        };
        if (meals.any(
          (meal) => meal.menu.any(
            (item) =>
                item.ko.toLowerCase().contains(keywordLower) ||
                (item.en?.toLowerCase().contains(keywordLower) ?? false),
          ),
        )) {
          matches.add(cafeteriaLabel);
        }
      }
    }

    if (matches.isNotEmpty) {
      matchesByKeyword[keyword] = matches;
    }
  }

  if (matchesByKeyword.isEmpty) return;

  final periodLabel = _periodLabel(period);
  final String title;
  final String body;
  if (matchesByKeyword.length == 1) {
    final entry = matchesByKeyword.entries.first;
    title = '$periodLabel "${entry.key}" 메뉴가 있어요!';
    body = entry.value.join(', ');
  } else {
    title = '$periodLabel 매칭된 메뉴가 있어요!';
    body = matchesByKeyword.entries
        .map((e) => '"${e.key}": ${e.value.join(', ')}')
        .join('\n');
  }

  await initNotifications();
  await showMealKeywordNotification(title: title, body: body);
}

String _periodLabel(MealAlertPeriod period) => switch (period) {
  MealAlertPeriod.morning => '오늘 아침',
  MealAlertPeriod.lunch => '오늘 점심',
  MealAlertPeriod.dinner => '오늘 저녁',
  MealAlertPeriod.night => '내일 아침',
};
