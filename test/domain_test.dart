import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';

void main() {
  group('MealTimeConfig.determineMealOfDay', () {
    test('09:00 → 아침', () {
      final t = DateTime(2026, 4, 13, 9, 0);
      expect(MealTimeConfig.determineMealOfDay(t), MealOfDay.breakfast);
    });

    test('09:20 → 아침 (경계값)', () {
      final t = DateTime(2026, 4, 13, 9, 20);
      expect(MealTimeConfig.determineMealOfDay(t), MealOfDay.breakfast);
    });

    test('09:21 → 점심', () {
      final t = DateTime(2026, 4, 13, 9, 21);
      expect(MealTimeConfig.determineMealOfDay(t), MealOfDay.lunch);
    });

    test('13:30 → 점심 (경계값)', () {
      final t = DateTime(2026, 4, 13, 13, 30);
      expect(MealTimeConfig.determineMealOfDay(t), MealOfDay.lunch);
    });

    test('13:31 → 저녁', () {
      final t = DateTime(2026, 4, 13, 13, 31);
      expect(MealTimeConfig.determineMealOfDay(t), MealOfDay.dinner);
    });

    test('23:59 → 저녁', () {
      final t = DateTime(2026, 4, 13, 23, 59);
      expect(MealTimeConfig.determineMealOfDay(t), MealOfDay.dinner);
    });

    test('00:00 → 아침', () {
      final t = DateTime(2026, 4, 13, 0, 0);
      expect(MealTimeConfig.determineMealOfDay(t), MealOfDay.breakfast);
    });
  });

  group('Cafeteria.fromApiKey', () {
    test('기숙사 식당 → dormitory', () {
      expect(Cafeteria.fromApiKey('기숙사 식당'), Cafeteria.dormitory);
    });

    test('학생 식당 → student', () {
      expect(Cafeteria.fromApiKey('학생 식당'), Cafeteria.student);
    });

    test('교직원 식당 → faculty', () {
      expect(Cafeteria.fromApiKey('교직원 식당'), Cafeteria.faculty);
    });

    test('알 수 없는 키 → FormatException', () {
      expect(() => Cafeteria.fromApiKey('unknown'), throwsFormatException);
    });
  });

  group('MealOfDay.fromApiKey', () {
    test('BREAKFAST → breakfast', () {
      expect(MealOfDay.fromApiKey('BREAKFAST'), MealOfDay.breakfast);
    });

    test('LUNCH → lunch', () {
      expect(MealOfDay.fromApiKey('LUNCH'), MealOfDay.lunch);
    });

    test('DINNER → dinner', () {
      expect(MealOfDay.fromApiKey('DINNER'), MealOfDay.dinner);
    });
  });

  group('MealOfDay.next', () {
    test('breakfast.next → lunch', () {
      expect(MealOfDay.breakfast.next, MealOfDay.lunch);
    });

    test('lunch.next → dinner', () {
      expect(MealOfDay.lunch.next, MealOfDay.dinner);
    });

    test('dinner.next → breakfast (wrap)', () {
      expect(MealOfDay.dinner.next, MealOfDay.breakfast);
    });
  });

  group('DayOfWeek.next', () {
    test('mon.next → tue', () {
      expect(DayOfWeek.mon.next, DayOfWeek.tue);
    });

    test('sun.next → mon (wrap)', () {
      expect(DayOfWeek.sun.next, DayOfWeek.mon);
    });
  });

  group('parseRawMeal', () {
    test('기본 JSON 파싱 — 기숙사 식당 한식 항목', () {
      final json = jsonEncode([
        {
          'dayType': 'MON',
          'mealType': 'BREAKFAST',
          'restaurantType': '기숙사 식당',
          'dormitoryType': 'KOREAN',
          'calorie': 500,
          'menus': ['쌀밥', '된장국'],
        },
      ]);
      final weekMeal = parseRawMeal(json);
      final meals =
          weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory];
      expect(meals.length, 1);
      expect(meals.first, isA<KoreanMeal>());
      expect(meals.first.menu, ['쌀밥', '된장국']);
      expect(meals.first.kcal, 500);
    });

    test('calorie 0 → kcal null', () {
      final json = jsonEncode([
        {
          'dayType': 'TUE',
          'mealType': 'LUNCH',
          'restaurantType': '학생 식당',
          'calorie': 0,
          'menus': ['김치찌개'],
        },
      ]);
      final weekMeal = parseRawMeal(json);
      final meals =
          weekMeal[DayOfWeek.tue][MealOfDay.lunch][Cafeteria.student];
      expect(meals.first.kcal, isNull);
    });

    test('할랄 항목은 HalalMeal', () {
      final json = jsonEncode([
        {
          'dayType': 'WED',
          'mealType': 'DINNER',
          'restaurantType': '기숙사 식당',
          'dormitoryType': 'HALAL',
          'calorie': 400,
          'menus': ['할랄밥'],
        },
      ]);
      final weekMeal = parseRawMeal(json);
      final meals =
          weekMeal[DayOfWeek.wed][MealOfDay.dinner][Cafeteria.dormitory];
      expect(meals.first, isA<HalalMeal>());
    });

    test('빈 JSON → 모든 식사 리스트가 비어 있음', () {
      final weekMeal = parseRawMeal(jsonEncode([]));
      expect(
        weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory],
        isEmpty,
      );
    });
  });
}
