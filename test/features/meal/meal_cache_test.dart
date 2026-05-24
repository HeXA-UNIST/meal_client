import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/meal/meal_cache.dart';

void main() {
  group('MealCache', () {
    test('raw JSON을 같은 파일 키로 저장하고 읽음', () async {
      final files = <String, String>{};
      final cache = MealCache(
        writeFile: (fileName, data) async => files[fileName] = data,
        readFile: (fileName) async => files[fileName]!,
        readLastModified: (_) async => DateTime.utc(2026, 4, 13),
      );

      await cache.writeRawMealJson('[{"dayType":"MON"}]');

      expect(await cache.readRawMealJson(), '[{"dayType":"MON"}]');
      expect(files.keys.single, 'meal.json');
    });

    test('lastModified가 현재 KST 주와 같으면 fresh', () async {
      final cache = MealCache(
        readLastModified: (_) async => DateTime.utc(2026, 1, 4, 15),
      );

      final result = await cache.hasFreshMealCache(
        DateTime.utc(2026, 1, 10, 14, 59),
      );

      expect(result, isTrue);
    });

    test('lastModified가 현재 KST 주와 다르면 stale', () async {
      final cache = MealCache(
        readLastModified: (_) async => DateTime.utc(2026, 1, 4, 14, 59),
      );

      final result = await cache.hasFreshMealCache(
        DateTime.utc(2026, 1, 4, 15),
      );

      expect(result, isFalse);
    });

    test('lastModified 조회가 실패하면 false', () async {
      final cache = MealCache(
        readLastModified: (_) async => throw Exception('no persistent cache'),
      );

      expect(await cache.hasFreshMealCache(DateTime.utc(2026)), isFalse);
    });
  });
}
