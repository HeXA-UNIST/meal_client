import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/meal/meal_cache.dart';

void main() {
  group('MealCache', () {
    test('raw JSON을 같은 파일 키로 저장하고 읽음', () async {
      final files = <String, String>{};
      final cache = MealCache(
        writeFile: (fileName, data) async => files[fileName] = data,
        readFile: (fileName) async => files[fileName]!,
      );

      await cache.writeRawMealJson(_rawMeal('2026-04-13'));

      expect(await cache.readRawMealJson(), _rawMeal('2026-04-13'));
      expect(files.keys.single, 'meal.json');
    });

    test('payload의 week start가 현재 KST 주와 같으면 fresh', () async {
      final cache = _cacheWithRaw(_rawMeal('2026-01-05'));

      expect(
        await cache.hasFreshMealCache(DateTime.utc(2026, 1, 10, 14, 59)),
        isTrue,
      );
    });

    test('payload가 다른 주면 mtime과 무관하게 stale', () async {
      final cache = _cacheWithRaw(_rawMeal('2025-12-29'));

      expect(
        await cache.hasFreshMealCache(DateTime.utc(2026, 1, 4, 15)),
        isFalse,
      );
    });

    test('KST 일요일에 기록된 next cache만 Sunday refresh 완료로 본다', () async {
      final cache = MealCache(
        readFile: (_) async => _rawMeal('2026-08-17'),
        readLastModified: (_) async => DateTime.utc(2026, 8, 23, 3),
      );

      expect(
        await cache.wasWrittenOnKstSunday(DateTime.utc(2026, 8, 23, 12)),
        isTrue,
      );
      expect(
        await cache.wasWrittenOnKstSunday(DateTime.utc(2026, 8, 24, 1)),
        isFalse,
      );
    });

    test('아직 생성되지 않은 cache 파일은 오류 로그 없이 miss로 처리한다', () async {
      final previousDebugPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);
      final cache = MealCache(
        readFile: (_) async => throw FileSystemException(
          '파일 없음',
          'meal-next.json',
          const OSError('No such file', 2),
        ),
      );

      final result = await cache.readValidatedMealForWeek(
        DateTime.utc(2026, 8, 17),
      );

      expect(result, isNull);
      expect(logs, isEmpty);
    });
  });
}

MealCache _cacheWithRaw(String raw) => MealCache(
  readFile: (_) async => raw,
  readLastModified: (_) async => DateTime.utc(2026),
);

String _rawMeal(String weekStart) => jsonEncode({
  'week': {
    'startDate': weekStart,
    'isCurrentWeek': true,
    'nextWeekStart': null,
  },
  'data': <Object?>[],
});
