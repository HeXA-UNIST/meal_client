import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';

/// 디버그 빌드에서 UI의 테스트 버튼이 호출하는 함수.
/// 백그라운드 태스크와 동일한 로직을 메인 isolate에서 즉시 실행한다.
/// [keywordsOverride]를 전달하면 SharedPreferences 값 대신 그 키워드 리스트로
/// 검사한다. (UI에서 막 입력한 값이 prefs에 아직 안 들어간 경우 활용)
Future<void> testMealKeywordCheck({List<String>? keywordsOverride}) =>
    _runMealKeywordCheck(keywordsOverride: keywordsOverride);

/// Workmanager 백그라운드 격리체(isolate) 진입점.
/// 이 함수는 앱 프로세스와 별개의 Dart isolate에서 실행된다.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kMealKeywordTaskName) {
      await _runMealKeywordCheck();
      // 다음날 같은 시각으로 태스크를 다시 등록
      await _rescheduleForNextDay();
    }
    return true;
  });
}

Future<void> _rescheduleForNextDay() async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(StorageKeys.notificationEnabled) ?? false;
  if (!enabled) return;

  final timeStr = prefs.getString(StorageKeys.notificationTime) ?? '8:0';
  final parts = timeStr.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8;
  final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  assert(() {
    debugPrint('[BapU] worker: rescheduling for next day at $hour:$minute');
    return true;
  }());
  await scheduleKeywordNotification(TimeOfDay(hour: hour, minute: minute));
  assert(() {
    debugPrint('[BapU] worker: reschedule call completed');
    return true;
  }());
}

Future<void> _runMealKeywordCheck({List<String>? keywordsOverride}) async {
  final prefs = await SharedPreferences.getInstance();

  final enabled = prefs.getBool(StorageKeys.notificationEnabled) ?? false;
  if (!enabled) return;

  // 키워드 로드 (override 또는 prefs). 공백 제거 + 빈 항목 제외.
  final rawKeywords = keywordsOverride ??
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

  // 백그라운드 isolate에서는 플랫폼별 HTTP 클라이언트 대신 기본 http 패키지 사용
  final http.Response response;
  try {
    response = await http
        .get(Uri.parse(ApiConstants.mealEndpoint))
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return;
  }
  if (response.statusCode != 200) return;

  final WeekMeal weekMeal;
  try {
    weekMeal = parseRawMeal(response.body);
  } catch (_) {
    return;
  }

  final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final today = DayOfWeek.values[kstNow.weekday - 1];

  // 키워드별 매칭 결과: { "떡갈비" -> ["기숙사 한식 점심"], "국" -> [...] }
  final matchesByKeyword = <String, List<String>>{};
  for (final keyword in keywords) {
    final keywordLower = keyword.toLowerCase();
    final matches = <String>[];

    for (final mealOfDay in MealOfDay.values) {
      final mealLabel = switch (mealOfDay) {
        MealOfDay.breakfast => '아침',
        MealOfDay.lunch => '점심',
        MealOfDay.dinner => '저녁',
      };
      for (final cafeteria in cafeterias) {
        final meals = weekMeal[today][mealOfDay][cafeteria];

        if (cafeteria == Cafeteria.dormitory) {
          // 기숙사는 한식·할랄을 각각 구분해 표시
          final seen = <String>{};
          for (final meal in meals) {
            if (!meal.menu
                .any((item) => item.toLowerCase().contains(keywordLower))) {
              continue;
            }
            final typeLabel = switch (meal) {
              KoreanMeal _ => ' 한식',
              HalalMeal _ => ' 할랄',
              _ => '',
            };
            final label = '기숙사$typeLabel $mealLabel';
            if (seen.add(label)) matches.add(label);
          }
        } else {
          final cafeteriaLabel = switch (cafeteria) {
            Cafeteria.dormitory => '기숙사', // unreachable
            Cafeteria.student => '학생',
            Cafeteria.faculty => '교직원',
          };
          if (meals.any((meal) => meal.menu
              .any((item) => item.toLowerCase().contains(keywordLower)))) {
            matches.add('$cafeteriaLabel $mealLabel');
          }
        }
      }
    }

    if (matches.isNotEmpty) {
      matchesByKeyword[keyword] = matches;
    }
  }

  if (matchesByKeyword.isEmpty) return;

  // 단일 키워드만 매칭 시 기존 단순 포맷, 여러 키워드 매칭 시 키워드별 그룹화
  final String title;
  final String body;
  if (matchesByKeyword.length == 1) {
    final entry = matchesByKeyword.entries.first;
    title = '오늘 "${entry.key}" 메뉴가 있어요!';
    body = entry.value.join(', ');
  } else {
    title = '오늘 매칭된 메뉴가 있어요!';
    body = matchesByKeyword.entries
        .map((e) => '"${e.key}": ${e.value.join(', ')}')
        .join('\n');
  }

  await initNotifications();
  await showMealKeywordNotification(title: title, body: body);
}
