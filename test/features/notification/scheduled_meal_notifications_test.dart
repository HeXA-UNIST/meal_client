import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/scheduled_meal_notifications.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/l10n/app_localizations_ko.dart';

void main() {
  test('기기 시간대와 day/night 경계에서 KST 대상 날짜를 보존한다', () {
    final targetDate = DateTime.utc(2026, 3, 30);
    for (final offsetHours in [-8, 0, 9, 13]) {
      for (final period in MealNotificationPeriod.values) {
        final fireInstant = fireInstantForTarget(
          period: period,
          targetKstDate: targetDate,
          alertTime: period.defaultSlot,
          localDateTimeFactory: (year, month, day, hour, minute) =>
              DateTime.utc(
                year,
                month,
                day,
                hour,
                minute,
              ).subtract(Duration(hours: offsetHours)),
        );

        expect(notificationTargetDateFor(period, fireInstant), targetDate);
      }
    }
  });

  test('고유 ID로 시간순 전체 슬롯만 예약 한도에 담는다', () {
    final currentWeek = _fullWeekWithMenus();
    final settings = NotificationSettings(
      enabled: true,
      alertTimes: const {
        MealNotificationPeriod.morning: TimeOfDay(hour: 8, minute: 0),
        MealNotificationPeriod.lunch: TimeOfDay(hour: 11, minute: 0),
      },
      cafeterias: Cafeteria.values.toSet(),
      dormMenuTypes: DormMenuType.values.toSet(),
      days: DayOfWeek.values.toSet(),
    );

    List<ScheduledMealNotification> build() => buildMealNotificationBatch(
      settings: settings,
      l10n: AppLocalizationsKo(),
      now: DateTime(2026, 7, 19, 10),
      currentWeek: (
        startDate: DateTime.utc(2026, 7, 20),
        weekMeal: currentWeek,
      ),
      maxNotifications: 5,
    );

    final first = build();
    final second = build();
    expect(first, hasLength(4));
    expect(first.map((item) => item.id).toSet(), hasLength(4));
    expect(
      first.every((item) => isScheduledMealNotificationId(item.id)),
      isTrue,
    );
    final requestsPerSlot = <DateTime, int>{};
    for (final item in first) {
      requestsPerSlot.update(
        item.fireInstant,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    expect(requestsPerSlot.values, everyElement(4));
    expect(
      first.map((item) => item.fireInstant),
      orderedEquals(first.map((item) => item.fireInstant).toList()..sort()),
    );
    expect(second.map((item) => item.id), first.map((item) => item.id));
  });

  test('두 플랫폼이 공유하는 64개 한도에서 전체 슬롯만 유지한다', () {
    final week = _fullWeekWithMenus();
    final settings = NotificationSettings(
      enabled: true,
      alertTimes: const {
        MealNotificationPeriod.morning: TimeOfDay(hour: 8, minute: 0),
        MealNotificationPeriod.lunch: TimeOfDay(hour: 11, minute: 0),
      },
      cafeterias: Cafeteria.values.toSet(),
      dormMenuTypes: DormMenuType.values.toSet(),
      days: DayOfWeek.values.toSet(),
    );
    final current = (startDate: DateTime.utc(2026, 7, 20), weekMeal: week);
    final next = (startDate: DateTime.utc(2026, 7, 27), weekMeal: week);

    final batch = buildMealNotificationBatch(
      settings: settings,
      l10n: AppLocalizationsKo(),
      now: DateTime(2026, 7, 19, 10),
      currentWeek: current,
      nextWeek: next,
    );

    expect(batch, hasLength(kMaxScheduledMealNotifications));
    final requestsPerSlot = <DateTime, int>{};
    for (final notification in batch) {
      requestsPerSlot.update(
        notification.fireInstant,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    expect(requestsPerSlot.values, everyElement(4));
  });

  group('예약 알림 pending reconciliation', () {
    final enabledSettings = NotificationSettings(
      enabled: true,
      alertTimes: const {
        MealNotificationPeriod.lunch: TimeOfDay(hour: 11, minute: 0),
      },
      cafeterias: const {Cafeteria.student},
      dormMenuTypes: const {},
      days: const {DayOfWeek.mon},
    );

    test('권한 또는 현재 주 데이터가 없으면 기존 pending을 보존한다', () async {
      var touchedData = false;
      await reconcileScheduledMealNotifications(
        settings: enabledSettings,
        readAuthorizationStatus: () async =>
            MealNotificationAuthorizationStatus.notAuthorized,
        loadCurrentWeek: () async {
          touchedData = true;
          return null;
        },
        readPendingIds: () async {
          touchedData = true;
          return const [];
        },
      );
      expect(touchedData, isFalse);

      final canceled = <int>[];
      await reconcileScheduledMealNotifications(
        settings: enabledSettings,
        readAuthorizationStatus: () async =>
            MealNotificationAuthorizationStatus.enabled,
        readPendingIds: () async => [_ownedId(DateTime.utc(2026, 7, 20))],
        cancelPending: (id) async => canceled.add(id),
        loadCurrentWeek: () async => null,
      );
      expect(canceled, isEmpty);
    });

    test('다음 주 실패 시 그 범위는 보존하고 다른 stale ID만 제거한다', () async {
      final nextWeekId = _ownedId(DateTime.utc(2026, 7, 27));
      final orphanedId = _ownedId(DateTime.utc(2026, 8, 3));
      final canceled = <int>[];

      await reconcileScheduledMealNotifications(
        settings: enabledSettings,
        currentWeek: (
          startDate: DateTime.utc(2026, 7, 20),
          weekMeal: WeekMeal.empty(),
        ),
        nowProvider: () => DateTime(2026, 7, 19, 10),
        readAuthorizationStatus: () async =>
            MealNotificationAuthorizationStatus.enabled,
        readPendingIds: () async => [nextWeekId, orphanedId, 42],
        cancelPending: (id) async => canceled.add(id),
        loadNextWeek: () async => null,
        upsertNotification: (_) async {},
        l10n: AppLocalizationsKo(),
      );

      expect(canceled, [orphanedId]);
    });

    test('다음 주 데이터가 없어도 현재 설정에서 해제한 pending은 취소한다', () async {
      final nextWeekId = _ownedId(DateTime.utc(2026, 7, 27));
      final canceled = <int>[];

      await reconcileScheduledMealNotifications(
        settings: enabledSettings.copyWith(
          cafeterias: const {Cafeteria.faculty},
        ),
        currentWeek: (
          startDate: DateTime.utc(2026, 7, 20),
          weekMeal: WeekMeal.empty(),
        ),
        nowProvider: () => DateTime(2026, 7, 19, 10),
        readAuthorizationStatus: () async =>
            MealNotificationAuthorizationStatus.enabled,
        readPendingIds: () async => [nextWeekId],
        cancelPending: (id) async => canceled.add(id),
        loadNextWeek: () async => null,
        upsertNotification: (_) async {},
        l10n: AppLocalizationsKo(),
      );

      expect(canceled, [nextWeekId]);
    });

    group('배달 대기 유예', () {
      final mondayLunchId = _ownedId(DateTime.utc(2026, 7, 20));
      final mondayLunchFireInstant = fireInstantForTarget(
        period: MealNotificationPeriod.lunch,
        targetKstDate: DateTime.utc(2026, 7, 20),
        alertTime: const TimeOfDay(hour: 11, minute: 0),
      );

      final dormKoreanLunchId = scheduledMealNotificationId(
        period: MealNotificationPeriod.lunch,
        contentId: 1,
        targetDate: DateTime.utc(2026, 7, 20),
        alertTime: const TimeOfDay(hour: 11, minute: 0),
      );

      Future<List<int>> reconcileAt(
        DateTime now, {
        NotificationSettings? settings,
        List<int>? pending,
      }) async {
        final canceled = <int>[];
        await reconcileScheduledMealNotifications(
          settings: settings ?? enabledSettings,
          currentWeek: (
            startDate: DateTime.utc(2026, 7, 20),
            weekMeal: _weekWithLunchMenus({DayOfWeek.mon}),
          ),
          nowProvider: () => now,
          readAuthorizationStatus: () async =>
              MealNotificationAuthorizationStatus.enabled,
          readPendingIds: () async => pending ?? [mondayLunchId],
          cancelPending: (id) async => canceled.add(id),
          loadNextWeek: () async => null,
          upsertNotification: (_) async {},
          l10n: AppLocalizationsKo(),
        );
        return canceled;
      }

      test('예약 시각 직후 재조정은 아직 배달되지 않은 pending을 남긴다', () async {
        expect(
          await reconcileAt(
            mondayLunchFireInstant.add(const Duration(seconds: 22)),
          ),
          isEmpty,
        );
      });

      test('유예가 끝나면 배달되지 않은 pending을 정리한다', () async {
        expect(
          await reconcileAt(
            mondayLunchFireInstant.add(
              kMealNotificationDeliveryGrace + const Duration(minutes: 1),
            ),
          ),
          [mondayLunchId],
        );
      });

      test('사용자가 끈 시간대는 유예 없이 취소한다', () async {
        expect(
          await reconcileAt(
            mondayLunchFireInstant.add(const Duration(seconds: 22)),
            settings: enabledSettings.copyWith(alertTimes: const {}),
          ),
          [mondayLunchId],
        );
      });

      test('사용자가 뺀 요일은 유예 없이 취소한다', () async {
        expect(
          await reconcileAt(
            mondayLunchFireInstant.add(const Duration(seconds: 22)),
            settings: enabledSettings.copyWith(days: const {DayOfWeek.tue}),
          ),
          [mondayLunchId],
        );
      });

      test('사용자가 해제한 식당은 유예 없이 취소한다', () async {
        expect(
          await reconcileAt(
            mondayLunchFireInstant.add(const Duration(seconds: 22)),
            settings: enabledSettings.copyWith(
              cafeterias: const {Cafeteria.faculty},
            ),
          ),
          [mondayLunchId],
        );
      });

      test('기숙사 메뉴 종류를 유지하면 유예 중 보존한다', () async {
        expect(
          await reconcileAt(
            mondayLunchFireInstant.add(const Duration(seconds: 22)),
            settings: enabledSettings.copyWith(
              dormMenuTypes: const {DormMenuType.korean},
            ),
            pending: [dormKoreanLunchId],
          ),
          isEmpty,
        );
      });

      test('사용자가 해제한 기숙사 메뉴 종류는 유예 없이 취소한다', () async {
        expect(
          await reconcileAt(
            mondayLunchFireInstant.add(const Duration(seconds: 22)),
            settings: enabledSettings.copyWith(
              dormMenuTypes: const {DormMenuType.halal},
            ),
            pending: [dormKoreanLunchId],
          ),
          [dormKoreanLunchId],
        );
      });

      test('더 이른 시각으로 변경하면 기존 시각의 pending을 보존하지 않는다', () async {
        final oldTimeId = scheduledMealNotificationId(
          period: MealNotificationPeriod.lunch,
          contentId: 3,
          targetDate: DateTime.utc(2026, 7, 20),
          alertTime: const TimeOfDay(hour: 11, minute: 30),
        );

        expect(
          await reconcileAt(
            mondayLunchFireInstant.subtract(const Duration(seconds: 20)),
            pending: [oldTimeId],
          ),
          [oldTimeId],
        );
      });
    });

    test('호출 사이에 과거가 된 scheduledDate만 건너뛴다', () async {
      var clockReads = 0;
      DateTime clock() => ++clockReads < 3
          ? DateTime(2026, 7, 19, 10)
          : DateTime(2026, 7, 20, 12);

      await reconcileScheduledMealNotifications(
        settings: enabledSettings,
        currentWeek: (
          startDate: DateTime.utc(2026, 7, 20),
          weekMeal: _weekWithLunchMenus({DayOfWeek.mon}),
        ),
        nowProvider: clock,
        readAuthorizationStatus: () async =>
            MealNotificationAuthorizationStatus.enabled,
        readPendingIds: () async => const [],
        loadNextWeek: () async => null,
        upsertNotification: (_) async => throw ArgumentError.value(
          DateTime(2026, 7, 20, 11),
          'scheduledDate',
        ),
        l10n: AppLocalizationsKo(),
      );
      await expectLater(
        reconcileScheduledMealNotifications(
          settings: enabledSettings,
          currentWeek: (
            startDate: DateTime.utc(2026, 7, 20),
            weekMeal: _weekWithLunchMenus({DayOfWeek.mon}),
          ),
          nowProvider: () => DateTime(2026, 7, 19, 10),
          readAuthorizationStatus: () async =>
              MealNotificationAuthorizationStatus.enabled,
          readPendingIds: () async => const [],
          loadNextWeek: () async => null,
          upsertNotification: (_) async => throw ArgumentError.value(
            DateTime(2026, 7, 20, 11),
            'scheduledDate',
          ),
          l10n: AppLocalizationsKo(),
        ),
        throwsArgumentError,
      );
    });

    test('개별 cancel과 upsert 실패 뒤에도 안전한 나머지를 모두 시도한다', () async {
      final staleId = _ownedId(DateTime.utc(2026, 8, 3));
      final upserted = <int>[];

      await expectLater(
        reconcileScheduledMealNotifications(
          settings: enabledSettings.copyWith(
            days: {DayOfWeek.mon, DayOfWeek.tue},
          ),
          currentWeek: (
            startDate: DateTime.utc(2026, 7, 20),
            weekMeal: _weekWithLunchMenus({DayOfWeek.mon, DayOfWeek.tue}),
          ),
          nowProvider: () => DateTime(2026, 7, 19, 10),
          readAuthorizationStatus: () async =>
              MealNotificationAuthorizationStatus.enabled,
          readPendingIds: () async => [staleId],
          cancelPending: (_) async => throw StateError('cancel failed'),
          loadNextWeek: () async => null,
          upsertNotification: (notification) async {
            upserted.add(notification.id);
            if (upserted.length == 1) throw ArgumentError('upsert failed');
          },
          l10n: AppLocalizationsKo(),
        ),
        throwsStateError,
      );

      expect(upserted, hasLength(2));
    });
  });

  test('owned pending 취소는 개별 실패 뒤에도 나머지를 시도한다', () async {
    final canceled = <int>[];
    final first = _ownedId(DateTime.utc(2026, 7, 20));
    final second = _ownedId(DateTime.utc(2026, 7, 21));

    await expectLater(
      cancelAllPendingMealNotifications(
        readPendingIds: () async => [first, 42, second],
        cancelPending: (id) async {
          canceled.add(id);
          if (id == first) throw StateError('cancel failed');
        },
      ),
      throwsStateError,
    );
    expect(canceled, [first, second]);
  });

  test('Android와 iOS만 각 플랫폼 예약기를 호출한다', () async {
    final calls = <MealNotificationPlatform>[];
    Future<void> androidOrIos(
      MealNotificationPlatform platform,
      NotificationSettings settings, {
      required bool Function() isCurrent,
    }) async {
      calls.add(platform);
    }

    for (final platform in MealNotificationPlatform.values) {
      await scheduleMealNotifications(
        NotificationSettings(),
        platform: platform,
        iosScheduler: (settings, {required isCurrent}) => androidOrIos(
          MealNotificationPlatform.ios,
          settings,
          isCurrent: isCurrent,
        ),
        androidScheduler: (settings, {required isCurrent}) => androidOrIos(
          MealNotificationPlatform.android,
          settings,
          isCurrent: isCurrent,
        ),
      );
    }

    expect(calls, [
      MealNotificationPlatform.android,
      MealNotificationPlatform.ios,
    ]);
  });
}

int _ownedId(DateTime targetDate) => scheduledMealNotificationId(
  period: MealNotificationPeriod.lunch,
  contentId: 3,
  targetDate: targetDate,
  alertTime: const TimeOfDay(hour: 11, minute: 0),
);

WeekMeal _weekWithLunchMenus(Set<DayOfWeek> days) {
  final week = WeekMeal.empty();
  for (final day in days) {
    final meals = week[day][MealOfDay.lunch];
    meals[Cafeteria.dormitory].addAll([_koreanMeal('한식'), _halalMeal('할랄')]);
    meals[Cafeteria.student].add(_meal('학생식'));
    meals[Cafeteria.faculty].add(_meal('교직원식'));
  }
  return week;
}

WeekMeal _fullWeekWithMenus() {
  final week = WeekMeal.empty();
  for (final day in DayOfWeek.values) {
    for (final mealOfDay in [MealOfDay.breakfast, MealOfDay.lunch]) {
      final meals = week[day][mealOfDay];
      meals[Cafeteria.dormitory].addAll([_koreanMeal('한식'), _halalMeal('할랄')]);
      meals[Cafeteria.student].add(_meal('학생식'));
      meals[Cafeteria.faculty].add(_meal('교직원식'));
    }
  }
  return week;
}

Meal _meal(String menu) => Meal.regular(menu: [MealMenuItem(ko: menu)]);

KoreanMeal _koreanMeal(String menu) => KoreanMeal(
  sections: [
    MealSection(
      type: MealSectionType.regular,
      menu: [MealMenuItem(ko: menu)],
    ),
  ],
);

HalalMeal _halalMeal(String menu) => HalalMeal(
  sections: [
    MealSection(
      type: MealSectionType.regular,
      menu: [MealMenuItem(ko: menu)],
    ),
  ],
);
