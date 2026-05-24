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

  group('MealTimeConfig.kstWeekId', () {
    test('같은 KST 주의 월요일과 일요일은 같은 ID', () {
      final mondayKst = DateTime.utc(2026, 4, 12, 15);
      final sundayKst = DateTime.utc(2026, 4, 19, 14, 59);

      expect(
        MealTimeConfig.kstWeekId(mondayKst),
        MealTimeConfig.kstWeekId(sundayKst),
      );
    });

    test('같은 KST 주는 UTC 연도 경계를 지나도 같은 ID', () {
      final jan1Kst = DateTime.utc(2025, 12, 31, 15);
      final sundayKst = DateTime.utc(2026, 1, 4, 14, 59);

      expect(
        MealTimeConfig.kstWeekId(jan1Kst),
        MealTimeConfig.kstWeekId(sundayKst),
      );
    });

    test('월요일 00:00 KST 경계에서 주 ID가 바뀜', () {
      final sunday2359Kst = DateTime.utc(2026, 1, 4, 14, 59);
      final monday0000Kst = DateTime.utc(2026, 1, 4, 15);

      expect(
        MealTimeConfig.kstWeekId(monday0000Kst),
        MealTimeConfig.kstWeekId(sunday2359Kst) + 1,
      );
    });

    test('1월 1일이 일요일이어도 전년도 마지막 주와 같은 ID', () {
      final dec31SatKst = DateTime.utc(2022, 12, 31, 14, 59);
      final jan1SunKst = DateTime.utc(2022, 12, 31, 15);

      expect(
        MealTimeConfig.kstWeekId(jan1SunKst),
        MealTimeConfig.kstWeekId(dec31SatKst),
      );
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
      final meals = weekMeal[DayOfWeek.tue][MealOfDay.lunch][Cafeteria.student];
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
