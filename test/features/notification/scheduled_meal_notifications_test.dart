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
      dormMealTypes: DormMealType.values.toSet(),
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

  test('iOS 한도와 Android의 제한 없는 2주 horizon을 구분한다', () {
    final week = _fullWeekWithMenus();
    final settings = NotificationSettings(
      enabled: true,
      alertTimes: const {
        MealNotificationPeriod.morning: TimeOfDay(hour: 8, minute: 0),
        MealNotificationPeriod.lunch: TimeOfDay(hour: 11, minute: 0),
      },
      cafeterias: Cafeteria.values.toSet(),
      dormMealTypes: DormMealType.values.toSet(),
      days: DayOfWeek.values.toSet(),
    );
    final current = (startDate: DateTime.utc(2026, 7, 20), weekMeal: week);
    final next = (startDate: DateTime.utc(2026, 7, 27), weekMeal: week);

    final ios = buildMealNotificationBatch(
      settings: settings,
      l10n: AppLocalizationsKo(),
      now: DateTime(2026, 7, 19, 10),
      currentWeek: current,
      nextWeek: next,
      maxNotifications: kMaxScheduledMealNotifications,
    );
    final android = buildMealNotificationBatch(
      settings: settings,
      l10n: AppLocalizationsKo(),
      now: DateTime(2026, 7, 19, 10),
      currentWeek: current,
      nextWeek: next,
      maxNotifications: null,
    );

    expect(ios, hasLength(64));
    expect(android, hasLength(112));
  });

  group('예약 알림 pending reconciliation', () {
    final enabledSettings = NotificationSettings(
      enabled: true,
      alertTimes: const {
        MealNotificationPeriod.lunch: TimeOfDay(hour: 11, minute: 0),
      },
      cafeterias: const {Cafeteria.student},
      dormMealTypes: const {},
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
