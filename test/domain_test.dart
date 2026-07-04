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

  group('MealMenuItem', () {
    test('한국어 locale은 ko를 반환한다', () {
      const item = MealMenuItem(ko: '쌀밥', en: 'Rice');

      expect(item.textFor('ko'), '쌀밥');
    });

    test('영어 locale은 en이 있으면 en을 반환한다', () {
      const item = MealMenuItem(ko: '쌀밥', en: 'Rice');

      expect(item.textFor('en'), 'Rice');
    });

    test('영어 locale에서 en이 null이면 ko로 폴백한다', () {
      const item = MealMenuItem(ko: '된장찌개');

      expect(item.textFor('en'), '된장찌개');
    });

    test('빈 en 문자열은 ko로 폴백한다', () {
      const item = MealMenuItem(ko: '김치', en: '');

      expect(item.textFor('en'), '김치');
    });
  });

  group('Cafeteria.fromApiKey', () {
    test('DORMITORY → dormitory', () {
      expect(Cafeteria.fromApiKey('DORMITORY'), Cafeteria.dormitory);
    });

    test('STUDENT → student', () {
      expect(Cafeteria.fromApiKey('STUDENT'), Cafeteria.student);
    });

    test('FACULTY → faculty', () {
      expect(Cafeteria.fromApiKey('FACULTY'), Cafeteria.faculty);
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

  group('DayOfWeek.fromApiKey', () {
    test('MON → mon', () {
      expect(DayOfWeek.fromApiKey('MON'), DayOfWeek.mon);
    });

    test('SUN → sun', () {
      expect(DayOfWeek.fromApiKey('SUN'), DayOfWeek.sun);
    });

    test('알 수 없는 키 → FormatException', () {
      expect(() => DayOfWeek.fromApiKey('UNKNOWN'), throwsFormatException);
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
    test('v2 JSON 파싱 — 기숙사 식당 한식과 할랄 항목', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': '2026-06-22',
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [
          {
            'cafeteria': 'DORMITORY',
            'meals': [
              {
                'date': '2026-06-15',
                'dayOfWeek': 'MON',
                'timeType': 'BREAKFAST',
                'menusByType': [
                  {
                    'menuType': 'KOREAN',
                    'sections': [
                      {
                        'sectionType': 'REGULAR',
                        'sectionTitle': {
                          'ko': '천원의 아침밥',
                          'en': '1,000 KRW Breakfast',
                        },
                        'calorie': 935,
                        'sectionAllergens': null,
                        'menus': [
                          {'ko': '쌀밥', 'en': 'Rice', 'allergens': []},
                          {
                            'ko': '황태해장국',
                            'en': 'Dried pollack soup',
                            'allergens': [1, 5],
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'menuType': 'HALAL',
                    'sections': [
                      {
                        'sectionType': 'REGULAR',
                        'sectionTitle': null,
                        'calorie': 958,
                        'sectionAllergens': null,
                        'menus': [
                          {'ko': '할랄밥', 'en': 'Halal rice', 'allergens': []},
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      final weekMeal = parseRawMeal(json);
      final meals =
          weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory];

      expect(meals.length, 2);
      expect(meals.first, isA<KoreanMeal>());
      expect(meals.first.localizedMenu('ko'), ['쌀밥', '황태해장국']);
      expect(meals.first.localizedMenu('en'), ['Rice', 'Dried pollack soup']);
      expect(meals.first.kcal, 935);
      expect(meals.last, isA<HalalMeal>());
      expect(meals.last.localizedMenu('en'), ['Halal rice']);
      expect(meals.last.kcal, 958);
    });

    test('영어 메뉴가 null이면 한국어로 폴백한다', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': null,
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [
          {
            'cafeteria': 'STUDENT',
            'meals': [
              {
                'date': '2026-06-16',
                'dayOfWeek': 'TUE',
                'timeType': 'LUNCH',
                'menusByType': [
                  {
                    'menuType': 'KOREAN',
                    'sections': [
                      {
                        'sectionType': 'REGULAR',
                        'sectionTitle': null,
                        'calorie': null,
                        'sectionAllergens': null,
                        'menus': [
                          {'ko': '된장찌개', 'en': null, 'allergens': null},
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      final weekMeal = parseRawMeal(json);
      final meals = weekMeal[DayOfWeek.tue][MealOfDay.lunch][Cafeteria.student];

      expect(meals.single.localizedMenu('en'), ['된장찌개']);
      expect(meals.single.kcal, isNull);
    });

    test('REGULAR 섹션만 표시하고 비REGULAR 섹션은 건너뛴다', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': null,
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [
          {
            'cafeteria': 'DORMITORY',
            'meals': [
              {
                'date': '2026-06-17',
                'dayOfWeek': 'WED',
                'timeType': 'DINNER',
                'menusByType': [
                  {
                    'menuType': 'KOREAN',
                    'sections': [
                      {
                        'sectionType': 'REGULAR',
                        'sectionTitle': null,
                        'calorie': 700,
                        'sectionAllergens': null,
                        'menus': [
                          {'ko': '쌀밥', 'en': 'Rice', 'allergens': []},
                        ],
                      },
                      {
                        'sectionType': 'CONVENIENCE',
                        'sectionTitle': {
                          'ko': '간편식 30개 한정',
                          'en': 'Grab-and-go meal, limited to 30 servings',
                        },
                        'calorie': 300,
                        'sectionAllergens': [1, 2],
                        'menus': [
                          {
                            'ko': '삼각김밥',
                            'en': 'Triangle gimbap',
                            'allergens': null,
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      final weekMeal = parseRawMeal(json);
      final meals =
          weekMeal[DayOfWeek.wed][MealOfDay.dinner][Cafeteria.dormitory];

      expect(meals.single.localizedMenu('ko'), ['쌀밥']);
      expect(meals.single.kcal, 700);
    });

    test('여러 REGULAR 섹션의 같은 칼로리도 단일 kcal로 표시하지 않는다', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': null,
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [
          {
            'cafeteria': 'DORMITORY',
            'meals': [
              {
                'date': '2026-06-18',
                'dayOfWeek': 'THU',
                'timeType': 'LUNCH',
                'menusByType': [
                  {
                    'menuType': 'KOREAN',
                    'sections': [
                      {
                        'sectionType': 'REGULAR',
                        'sectionTitle': null,
                        'calorie': 700,
                        'sectionAllergens': null,
                        'menus': [
                          {'ko': '쌀밥', 'en': 'Rice', 'allergens': []},
                        ],
                      },
                      {
                        'sectionType': 'REGULAR',
                        'sectionTitle': null,
                        'calorie': 700,
                        'sectionAllergens': null,
                        'menus': [
                          {
                            'ko': '된장국',
                            'en': 'Soybean paste soup',
                            'allergens': [],
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      final weekMeal = parseRawMeal(json);
      final meals =
          weekMeal[DayOfWeek.thu][MealOfDay.lunch][Cafeteria.dormitory];

      expect(meals.single.localizedMenu('ko'), ['쌀밥', '된장국']);
      expect(meals.single.kcal, isNull);
    });

    test('REGULAR 섹션이 없으면 메뉴 카드를 만들지 않는다', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': null,
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [
          {
            'cafeteria': 'STUDENT',
            'meals': [
              {
                'date': '2026-06-19',
                'dayOfWeek': 'FRI',
                'timeType': 'LUNCH',
                'menusByType': [
                  {
                    'menuType': 'KOREAN',
                    'sections': [
                      {
                        'sectionType': 'SPECIAL',
                        'sectionTitle': {'ko': '일품코너', 'en': null},
                        'calorie': null,
                        'sectionAllergens': null,
                        'menus': [
                          {'ko': '돈까스정식', 'en': null, 'allergens': null},
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      final weekMeal = parseRawMeal(json);
      final meals = weekMeal[DayOfWeek.fri][MealOfDay.lunch][Cafeteria.student];

      expect(meals, isEmpty);
    });

    test('필수 메뉴 ko가 null이면 FormatException을 던진다', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': null,
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [
          {
            'cafeteria': 'DORMITORY',
            'meals': [
              {
                'date': '2026-06-20',
                'dayOfWeek': 'SAT',
                'timeType': 'BREAKFAST',
                'menusByType': [
                  {
                    'menuType': 'KOREAN',
                    'sections': [
                      {
                        'sectionType': 'REGULAR',
                        'sectionTitle': null,
                        'calorie': null,
                        'sectionAllergens': null,
                        'menus': [
                          {'ko': null, 'en': 'Rice', 'allergens': []},
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });

      expect(() => parseRawMeal(json), throwsFormatException);
    });

    test('필수 목록 필드가 null이면 FormatException을 던진다', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': null,
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': null,
      });

      expect(() => parseRawMeal(json), throwsFormatException);
    });

    test('data가 빈 배열이면 모든 식사 리스트가 비어 있음', () {
      final weekMeal = parseRawMeal(
        jsonEncode({
          'week': {
            'startDate': '2026-06-15',
            'isCurrentWeek': true,
            'nextWeekStart': null,
          },
          'lastUpdated': '2026-06-15T09:00:00+09:00',
          'data': [],
        }),
      );

      expect(
        weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory],
        isEmpty,
      );
    });
  });
}
