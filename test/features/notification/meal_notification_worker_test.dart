import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';

void main() {
  group('notification background cache refresh', () {
    test('meal cache refresh가 성공하면 info fetch 실패만으로 task를 실패시키지 않음', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async => throw Exception('info unavailable'),
      );

      expect(result, isTrue);
    });

    test('meal cache refresh 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async => throw Exception('meal unavailable'),
        refreshInfoCache: () async {},
      );

      expect(result, isFalse);
    });

    test('info cache write 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async =>
            throw InfoCacheWriteException(Exception('disk full')),
      );

      expect(result, isFalse);
    });

    test('meal과 info cache refresh를 병렬로 시작', () async {
      var mealCompleted = false;
      var infoStartedBeforeMealCompleted = false;

      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          mealCompleted = true;
        },
        refreshInfoCache: () async {
          infoStartedBeforeMealCompleted = !mealCompleted;
        },
      );

      expect(result, isTrue);
      expect(infoStartedBeforeMealCompleted, isTrue);
    });
  });
}
