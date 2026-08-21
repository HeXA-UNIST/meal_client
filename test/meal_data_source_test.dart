import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';

void main() {
  test('동시에 시작한 canonical foreground 갱신은 하나의 network 결과를 공유한다', () async {
    final response = Completer<MealResponse>();
    var refreshCount = 0;
    Future<MealResponse> refresh() {
      refreshCount++;
      return response.future;
    }

    final first = runForegroundMealRefresh(refresh);
    final second = runForegroundMealRefresh(refresh);
    response.complete((
      weekMeal: WeekMeal.empty(),
      weekMeta: parseWeekMeta(_rawMeal('2026-04-20', isCurrentWeek: true)),
    ));

    expect(await first, await second);
    expect(refreshCount, 1);
  });

  group('fetchMealDataForWeek', () {
    test('주어진 날짜로 /v2/menu/{date} 형태의 URL을 요청한다', () async {
      String? requestedUrl;
      Future<String> fakeFetch(String url) async {
        requestedUrl = url;
        return '{"week":{"startDate":"2026-06-22","isCurrentWeek":false,"nextWeekStart":null},'
            '"lastUpdated":"2026-06-22T09:00:00+09:00","data":[]}';
      }

      final weekMeal = await fetchMealDataForWeek(
        '2026-06-22',
        fetch: fakeFetch,
      );

      expect(requestedUrl, 'https://meal.hexa.pro/v2/menu/2026-06-22');
      expect(
        weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory],
        isEmpty,
      );
    });

    test('응답 데이터를 WeekMeal로 파싱한다', () async {
      Future<String> fakeFetch(String url) async {
        return '{"week":{"startDate":"2026-06-22","isCurrentWeek":false,"nextWeekStart":null},'
            '"lastUpdated":"2026-06-22T09:00:00+09:00",'
            '"data":[{"cafeteria":"DORMITORY","meals":[{"date":"2026-06-22",'
            '"dayOfWeek":"MON","timeType":"BREAKFAST","menusByType":['
            '{"menuType":"KOREAN","sections":[{"sectionType":"REGULAR",'
            '"sectionTitle":null,"calorie":500,"sectionAllergens":null,'
            '"menus":[{"ko":"쌀밥","en":"Rice","allergens":[]}]}]}]}]}]}';
      }

      final weekMeal = await fetchMealDataForWeek(
        '2026-06-22',
        fetch: fakeFetch,
      );
      final meals =
          weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory];

      expect(meals.single.localizedMenu('ko'), ['쌀밥']);
      expect(meals.single.kcal, 500);
    });
  });

  group('getCachedMealData', () {
    final monday = DateTime.utc(2026, 4, 19, 15);

    test('같은 주 파일 둘이 있으면 canonical meal json을 우선한다', () async {
      final response = await getCachedMealData(
        now: monday,
        cache: _memoryCache(_rawMeal('2026-04-20', isCurrentWeek: true)),
        nextWeekCache: _memoryCache(
          _rawMeal('2026-04-20', isCurrentWeek: false),
        ),
      );

      expect(response.weekMeta.isCurrentWeek, isTrue);
    });

    test('canonical이 다른 주면 일치하는 next cache를 사용한다', () async {
      final response = await getCachedMealData(
        now: monday,
        cache: _memoryCache(_rawMeal('2026-04-13', isCurrentWeek: true)),
        nextWeekCache: _memoryCache(
          _rawMeal('2026-04-20', isCurrentWeek: false),
        ),
      );

      expect(response.weekMeta.isCurrentWeek, isFalse);
    });

    test('손상된 canonical은 일치하는 next cache로 폴백한다', () async {
      final response = await getCachedMealData(
        now: monday,
        cache: _memoryCache(
          '{"week":{"startDate":"2026-04-20","isCurrentWeek":true,"nextWeekStart":null},"data":"broken"}',
        ),
        nextWeekCache: _memoryCache(
          _rawMeal('2026-04-20', isCurrentWeek: false),
        ),
      );

      expect(response.weekMeta.isCurrentWeek, isFalse);
    });

    test('일치하는 파일이 없으면 이전 주 메뉴를 사용하지 않는다', () async {
      await expectLater(
        getCachedMealData(
          now: monday,
          cache: _memoryCache(_rawMeal('2026-04-13', isCurrentWeek: true)),
          nextWeekCache: _memoryCache(
            _rawMeal('2026-04-13', isCurrentWeek: false),
          ),
        ),
        throwsException,
      );
    });
  });
}

MealCache _memoryCache(String raw) => MealCache(readFile: (_) async => raw);

String _rawMeal(String weekStart, {required bool isCurrentWeek}) => jsonEncode({
  'week': {
    'startDate': weekStart,
    'isCurrentWeek': isCurrentWeek,
    'nextWeekStart': null,
  },
  'data': <Object?>[],
});
