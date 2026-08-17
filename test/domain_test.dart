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
      expect(meals.first.sections.single.type, MealSectionType.regular);
      expect(meals.first.sections.single.title?.textFor('ko'), '천원의 아침밥');
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

    test('REGULAR 칼로리를 기본값으로 유지하며 SALAD를 제외한다', () {
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

      expect(meals.single.localizedMenu('ko'), ['쌀밥', '삼각김밥']);
      expect(meals.single.kcal, 700);
      expect(meals.single.sections, hasLength(2));
      expect(meals.single.sections.last.type, MealSectionType.convenience);
      expect(
        meals.single.sections.last.title?.textFor('en'),
        'Grab-and-go meal, limited to 30 servings',
      );
      expect(meals.single.sections.last.kcal, 300);
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

    test('SPECIAL 섹션만 있어도 메뉴 카드를 만든다', () {
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

      expect(meals, hasLength(1));
      expect(meals.single.sections.single.type, MealSectionType.special);
      expect(meals.single.localizedMenu('ko'), ['돈까스정식']);
    });

    test('누락되거나 비어 있는 섹션 제목은 제목 없음으로 처리한다', () {
      final weekMeal = parseRawMeal(
        jsonEncode({
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
                  'date': '2026-06-15',
                  'dayOfWeek': 'MON',
                  'timeType': 'LUNCH',
                  'menusByType': [
                    {
                      'menuType': 'KOREAN',
                      'sections': [
                        {
                          'sectionType': 'CONVENIENCE',
                          'sectionTitle': {'en': 'Missing Korean title'},
                          'calorie': null,
                          'sectionAllergens': null,
                          'menus': [
                            {'ko': '간편식 A', 'en': null, 'allergens': null},
                          ],
                        },
                        {
                          'sectionType': 'SPECIAL',
                          'sectionTitle': {
                            'ko': null,
                            'en': 'Null Korean title',
                          },
                          'calorie': null,
                          'sectionAllergens': null,
                          'menus': [
                            {'ko': '특별식 B', 'en': null, 'allergens': null},
                          ],
                        },
                        {
                          'sectionType': 'SPECIAL',
                          'sectionTitle': {
                            'ko': '   ',
                            'en': 'Blank Korean title',
                          },
                          'calorie': null,
                          'sectionAllergens': null,
                          'menus': [
                            {'ko': '특별식 C', 'en': null, 'allergens': null},
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        }),
      );

      final meal =
          weekMeal[DayOfWeek.mon][MealOfDay.lunch][Cafeteria.dormitory].single;

      expect(meal.sections, hasLength(3));
      expect(
        meal.sections.map((section) => section.title),
        everyElement(isNull),
      );
      expect(
        meal.sections.first.titleFor(
          'ko',
          convenienceLabel: '간편식',
          specialLabel: '특별식',
        ),
        '간편식',
      );
    });

    test('알 수 없는 섹션 타입은 건너뛰고 나머지 메뉴를 표시한다', () {
      final weekMeal = parseRawMeal(
        jsonEncode({
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
                  'date': '2026-06-15',
                  'dayOfWeek': 'MON',
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
                          'sectionType': 'FUTURE_TYPE',
                          'sectionTitle': null,
                          'calorie': null,
                          'sectionAllergens': null,
                          'menus': [
                            {'ko': '새 메뉴', 'en': null, 'allergens': null},
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        }),
      );

      final meals =
          weekMeal[DayOfWeek.mon][MealOfDay.lunch][Cafeteria.dormitory];

      expect(meals.single.localizedMenu('ko'), ['쌀밥']);
      expect(meals.single.kcal, 700);
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

  group('parseWeekMeta', () {
    test('week 객체를 파싱한다 — nextWeekStart가 있는 경우', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': '2026-06-22',
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [],
      });

      final weekMeta = parseWeekMeta(json);

      expect(weekMeta.startDate, DateTime.parse('2026-06-15'));
      expect(weekMeta.isCurrentWeek, true);
      expect(weekMeta.nextWeekStart, '2026-06-22');
    });

    test('week 객체를 파싱한다 — nextWeekStart가 null인 경우', () {
      final json = jsonEncode({
        'week': {
          'startDate': '2026-06-15',
          'isCurrentWeek': true,
          'nextWeekStart': null,
        },
        'lastUpdated': '2026-06-15T09:00:00+09:00',
        'data': [],
      });

      final weekMeta = parseWeekMeta(json);

      expect(weekMeta.nextWeekStart, isNull);
    });

    test('week startDate는 월요일 YYYY-MM-DD 형식만 허용한다', () {
      expect(() => parseWeekStartDate('2026-6-22'), throwsFormatException);
      expect(() => parseWeekStartDate('2026-06-23'), throwsFormatException);
      expect(parseWeekStartDate('2026-06-22'), DateTime(2026, 6, 22));
    });
  });
}
