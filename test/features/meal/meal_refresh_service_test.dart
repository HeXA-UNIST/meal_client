import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';

void main() {
  group('MealRefreshService', () {
    test('fresh cache가 있으면 네트워크 fetch 없이 캐시를 사용', () async {
      var fetchCount = 0;
      final cache = _memoryMealCache(
        rawJson: _rawMealJson('쌀밥'),
        updatedAt: DateTime.utc(2026, 4, 13),
      );
      final service = MealRefreshService(
        cache: cache,
        fetchRaw: (_) async {
          fetchCount++;
          return _rawMealJson('새 메뉴');
        },
      );

      final weekMeal = await service.getFreshOrRefreshMealData(
        now: DateTime.utc(2026, 4, 14),
      );

      expect(fetchCount, 0);
      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('쌀밥'));
    });

    test('stale cache면 fetch 후 raw JSON을 저장', () async {
      var storedRaw = _rawMealJson('오래된 메뉴');
      final cache = _memoryMealCache(
        rawJson: storedRaw,
        updatedAt: DateTime.utc(2026, 1, 4, 14, 59),
        onWrite: (rawJson) => storedRaw = rawJson,
      );
      final service = MealRefreshService(
        cache: cache,
        fetchRaw: (_) async => _rawMealJson('새 메뉴'),
      );

      final weekMeal = await service.getFreshOrRefreshMealData(
        now: DateTime.utc(2026, 1, 4, 15),
      );

      expect(storedRaw, _rawMealJson('새 메뉴'));
      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('새 메뉴'));
    });

    test('fresh cache 파싱이 실패하면 fetch로 복구', () async {
      var fetchCount = 0;
      final cache = _memoryMealCache(
        rawJson: '{broken',
        updatedAt: DateTime.utc(2026, 4, 13),
      );
      final service = MealRefreshService(
        cache: cache,
        fetchRaw: (_) async {
          fetchCount++;
          return _rawMealJson('복구 메뉴');
        },
      );

      final weekMeal = await service.getFreshOrRefreshMealData(
        now: DateTime.utc(2026, 4, 14),
      );

      expect(fetchCount, 1);
      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('복구 메뉴'));
    });

    test('refreshMealData는 항상 fetch 결과를 저장하고 파싱', () async {
      String? storedRaw;
      final cache = _memoryMealCache(
        rawJson: _rawMealJson('이전 메뉴'),
        updatedAt: DateTime.utc(2026, 4, 13),
        onWrite: (rawJson) => storedRaw = rawJson,
      );
      final service = MealRefreshService(
        cache: cache,
        fetchRaw: (_) async => _rawMealJson('다운로드 메뉴'),
      );

      final weekMeal = await service.refreshMealData();

      expect(storedRaw, _rawMealJson('다운로드 메뉴'));
      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('다운로드 메뉴'));
    });

    test('refreshMealResponse는 식단과 주차 메타데이터를 함께 반환', () async {
      final cache = _memoryMealCache(
        rawJson: _rawMealJson('이전 메뉴'),
        updatedAt: DateTime.utc(2026, 4, 13),
      );
      final service = MealRefreshService(
        cache: cache,
        fetchRaw: (_) async => _rawMealJson('다운로드 메뉴'),
      );

      final result = await service.refreshMealResponse();

      expect(
        _firstDormitoryBreakfastMenu(result.weekMeal),
        contains('다운로드 메뉴'),
      );
      expect(result.weekMeta.startDate, DateTime(2026, 4, 13));
      expect(result.weekMeta.isCurrentWeek, isTrue);
      expect(result.weekMeta.nextWeekStart, isNull);
    });

    test('refreshMealData는 JSON 객체 응답을 캐시에 쓰지 않음', () async {
      String? storedRaw;
      final cache = _memoryMealCache(
        rawJson: _rawMealJson('이전 메뉴'),
        updatedAt: DateTime.utc(2026, 4, 13),
        onWrite: (rawJson) => storedRaw = rawJson,
      );
      final service = MealRefreshService(
        cache: cache,
        fetchRaw: (_) async => '{"error":"temporary"}',
      );

      await expectLater(service.refreshMealData(), throwsFormatException);

      expect(storedRaw, isNull);
    });

    test('refreshMealData는 빈 배열 응답을 캐시에 쓰지 않음', () async {
      String? storedRaw;
      final cache = _memoryMealCache(
        rawJson: _rawMealJson('이전 메뉴'),
        updatedAt: DateTime.utc(2026, 4, 13),
        onWrite: (rawJson) => storedRaw = rawJson,
      );
      final service = MealRefreshService(
        cache: cache,
        fetchRaw: (_) async => '[]',
      );

      await expectLater(service.refreshMealData(), throwsFormatException);

      expect(storedRaw, isNull);
    });
    test('refreshMealData는 기본적으로 캐시 쓰기 실패를 무시', () async {
      final service = MealRefreshService(
        cache: MealCache(
          writeFile: (_, _) async => throw Exception('disk full'),
          readFile: (_) async => _rawMealJson('이전 메뉴'),
          readLastModified: (_) async => DateTime.utc(2026, 4, 13),
        ),
        fetchRaw: (_) async => _rawMealJson('다운로드 메뉴'),
      );

      final weekMeal = await service.refreshMealData();

      expect(_firstDormitoryBreakfastMenu(weekMeal), contains('다운로드 메뉴'));
    });

    test('refreshMealData는 background strict 모드에서 캐시 쓰기 실패를 throw', () async {
      final service = MealRefreshService(
        cache: MealCache(
          writeFile: (_, _) async => throw Exception('disk full'),
          readFile: (_) async => _rawMealJson('이전 메뉴'),
          readLastModified: (_) async => DateTime.utc(2026, 4, 13),
        ),
        fetchRaw: (_) async => _rawMealJson('다운로드 메뉴'),
        throwOnCacheWriteFailure: true,
      );

      await expectLater(service.refreshMealData(), throwsException);
    });
  });
}

MealCache _memoryMealCache({
  required String rawJson,
  required DateTime updatedAt,
  void Function(String rawJson)? onWrite,
}) {
  var currentRawJson = rawJson;
  return MealCache(
    writeFile: (_, data) async {
      currentRawJson = data;
      onWrite?.call(data);
    },
    readFile: (_) async => currentRawJson,
    readLastModified: (_) async => updatedAt,
  );
}

String _rawMealJson(String menu) {
  return jsonEncode({
    'week': {
      'startDate': '2026-04-13',
      'isCurrentWeek': true,
      'nextWeekStart': null,
    },
    'lastUpdated': '2026-04-13T09:00:00+09:00',
    'data': [
      {
        'cafeteria': 'DORMITORY',
        'meals': [
          {
            'date': '2026-04-13',
            'dayOfWeek': 'MON',
            'timeType': 'BREAKFAST',
            'menusByType': [
              {
                'menuType': 'KOREAN',
                'sections': [
                  {
                    'sectionType': 'REGULAR',
                    'sectionTitle': null,
                    'calorie': 500,
                    'sectionAllergens': null,
                    'menus': [
                      {'ko': menu, 'en': null, 'allergens': null},
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
}

List<String> _firstDormitoryBreakfastMenu(WeekMeal weekMeal) {
  return weekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory].first
      .localizedMenu('ko');
}
