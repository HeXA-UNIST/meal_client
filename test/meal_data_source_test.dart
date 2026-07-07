import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';

void main() {
  group('fetchNextWeekMealData', () {
    test('주어진 날짜로 /v2/menu/{date} 형태의 URL을 요청한다', () async {
      String? requestedUrl;
      Future<String> fakeFetch(String url) async {
        requestedUrl = url;
        return '{"week":{"startDate":"2026-06-22","isCurrentWeek":false,"nextWeekStart":null},'
            '"lastUpdated":"2026-06-22T09:00:00+09:00","data":[]}';
      }

      final weekMeal = await fetchNextWeekMealData(
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

      final weekMeal = await fetchNextWeekMealData(
        '2026-06-22',
        fetch: fakeFetch,
      );
      final meals =
          weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory];

      expect(meals.single.localizedMenu('ko'), ['쌀밥']);
      expect(meals.single.kcal, 500);
    });
  });
}
