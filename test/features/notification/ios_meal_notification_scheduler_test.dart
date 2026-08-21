import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/ios_meal_notification_scheduler.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/l10n/app_localizations_ko.dart';

void main() {
  group('iOS 알림 시각 역변환', () {
    test('기기 UTC offset과 시간대 종류에 관계없이 KST 대상 날짜로 왕복한다', () {
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
  });

  group('iOS 알림 배치', () {
    test('식당별 ID를 분리하고 64개 한도에서는 시간 슬롯 전체만 보존한다', () {
      final week = _weekWithLunchMenus({DayOfWeek.mon, DayOfWeek.tue});
      final settings = NotificationSettings(
        enabled: true,
        alertTimes: const {
          MealNotificationPeriod.lunch: TimeOfDay(hour: 11, minute: 0),
        },
        cafeterias: const {Cafeteria.student, Cafeteria.faculty},
        dormMealTypes: DormMealType.values.toSet(),
        days: const {DayOfWeek.mon, DayOfWeek.tue},
      );

      final batch = buildMealNotificationBatch(
        settings: settings,
        l10n: AppLocalizationsKo(),
        now: DateTime(2026, 7, 19, 10),
        currentWeek: (startDate: DateTime.utc(2026, 7, 20), weekMeal: week),
        maxNotifications: 5,
      );

      expect(batch, hasLength(4));
      expect(batch.map((item) => item.id).toSet(), hasLength(4));
      expect(
        batch.every((item) => isScheduledMealNotificationId(item.id)),
        isTrue,
      );
      expect(batch.map((item) => item.fireInstant).toSet(), hasLength(1));
    });

    test('활성 요일은 night 실행일이 아니라 KST 메뉴 대상일에 적용한다', () {
      final week = _weekWithBreakfastMenu(DayOfWeek.mon);
      final settings = NotificationSettings(
        enabled: true,
        alertTimes: const {
          MealNotificationPeriod.night: TimeOfDay(hour: 21, minute: 30),
        },
        cafeterias: const {Cafeteria.student},
        dormMealTypes: const {},
        days: const {DayOfWeek.mon},
      );

      final batch = buildMealNotificationBatch(
        settings: settings,
        l10n: AppLocalizationsKo(),
        now: DateTime(2026, 7, 19, 10),
        currentWeek: (startDate: DateTime.utc(2026, 7, 20), weekMeal: week),
      );

      expect(batch, hasLength(1));
      expect(
        notificationTargetDateFor(
          MealNotificationPeriod.night,
          batch.single.fireInstant,
        ),
        DateTime.utc(2026, 7, 20),
      );
    });
  });

  group('iOS pending reconciliation', () {
    final enabledSettings = NotificationSettings(
      enabled: true,
      alertTimes: const {
        MealNotificationPeriod.lunch: TimeOfDay(hour: 11, minute: 0),
      },
      cafeterias: const {Cafeteria.student},
      dormMealTypes: const {},
      days: const {DayOfWeek.mon},
    );

    test('권한이 없으면 캐시와 pending 요청을 전혀 읽거나 변경하지 않는다', () async {
      var touchedData = false;
      final outcome = await reconcileIosMealNotifications(
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

      expect(outcome, IosMealReconciliationOutcome.notAuthorized);
      expect(touchedData, isFalse);
    });

    test('데이터 갱신에서 현재 주 캐시가 없으면 기존 예약을 보존한다', () async {
      final canceled = <int>[];
      final existingId = scheduledMealNotificationId(
        period: MealNotificationPeriod.lunch,
        contentId: 3,
        targetDate: DateTime.utc(2026, 7, 20),
      );

      final outcome = await reconcileIosMealNotifications(
        settings: enabledSettings,
        readAuthorizationStatus: () async =>
            MealNotificationAuthorizationStatus.enabled,
        readPendingIds: () async => [existingId],
        cancelPending: (id) async => canceled.add(id),
        loadCurrentWeek: () async => null,
      );

      expect(outcome, IosMealReconciliationOutcome.currentWeekUnavailable);
      expect(canceled, isEmpty);
    });

    test('다음 주 로드 실패는 다음 주 예약만 보존하고 다른 stale ID만 제거한다', () async {
      final nextWeekId = scheduledMealNotificationId(
        period: MealNotificationPeriod.lunch,
        contentId: 3,
        targetDate: DateTime.utc(2026, 7, 27),
      );
      final orphanedId = scheduledMealNotificationId(
        period: MealNotificationPeriod.lunch,
        contentId: 3,
        targetDate: DateTime.utc(2026, 8, 3),
      );
      final canceled = <int>[];

      await reconcileIosMealNotifications(
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

    test('사용자 설정 변경은 기존 예약을 먼저 취소하고 새 배치를 등록한다', () async {
      final oldId = scheduledMealNotificationId(
        period: MealNotificationPeriod.lunch,
        contentId: 4,
        targetDate: DateTime.utc(2026, 7, 20),
      );
      final canceled = <int>[];
      final scheduled = <ScheduledMealNotification>[];

      final outcome = await reconcileIosMealNotifications(
        settings: enabledSettings,
        clearPendingFirst: true,
        currentWeek: (
          startDate: DateTime.utc(2026, 7, 20),
          weekMeal: _weekWithLunchMenus({DayOfWeek.mon}),
        ),
        nowProvider: () => DateTime(2026, 7, 19, 10),
        readAuthorizationStatus: () async =>
            MealNotificationAuthorizationStatus.enabled,
        readPendingIds: () async => [oldId],
        cancelPending: (id) async => canceled.add(id),
        loadNextWeek: () async => null,
        upsertNotification: (notification) async => scheduled.add(notification),
        l10n: AppLocalizationsKo(),
      );

      expect(outcome, IosMealReconciliationOutcome.scheduled);
      expect(canceled, [oldId]);
      expect(scheduled, hasLength(1));
      expect(scheduled.single.title, contains('학생 식당'));
    });

    test('배치 중 두 번째 platform upsert 실패를 호출자에게 전달한다', () async {
      var upsertCount = 0;
      final twoCafeterias = enabledSettings.copyWith(
        cafeterias: {Cafeteria.student, Cafeteria.faculty},
      );

      await expectLater(
        reconcileIosMealNotifications(
          settings: twoCafeterias,
          currentWeek: (
            startDate: DateTime.utc(2026, 7, 20),
            weekMeal: _weekWithLunchMenus({DayOfWeek.mon}),
          ),
          nowProvider: () => DateTime(2026, 7, 19, 10),
          readAuthorizationStatus: () async =>
              MealNotificationAuthorizationStatus.enabled,
          readPendingIds: () async => const [],
          loadNextWeek: () async => null,
          upsertNotification: (_) async {
            upsertCount++;
            if (upsertCount == 2) throw StateError('platform failure');
          },
          l10n: AppLocalizationsKo(),
        ),
        throwsStateError,
      );
      expect(upsertCount, 2);
    });

    test('upsert 사이에 지난 scheduledDate 오류만 건너뛴다', () async {
      var clockReads = 0;
      DateTime clock() => ++clockReads < 3
          ? DateTime(2026, 7, 19, 10)
          : DateTime(2026, 7, 20, 12);

      final outcome = await reconcileIosMealNotifications(
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

      expect(outcome, IosMealReconciliationOutcome.scheduled);
    });

    test('아직 미래인 scheduledDate 오류는 숨기지 않는다', () async {
      await expectLater(
        reconcileIosMealNotifications(
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
  });

  test('owned pending 취소는 다른 기능의 ID를 보존한다', () async {
    final ownedId = scheduledMealNotificationId(
      period: MealNotificationPeriod.lunch,
      contentId: 3,
      targetDate: DateTime.utc(2026, 7, 20),
    );
    final canceled = <int>[];

    await cancelAllPendingMealNotifications(
      readPendingIds: () async => [ownedId, 42],
      cancelPending: (id) async => canceled.add(id),
    );

    expect(canceled, [ownedId]);
  });

  test('플랫폼 분기는 iOS에서 Workmanager 예약 콜백을 호출하지 않는다', () async {
    var iosCalls = 0;
    var androidCalls = 0;
    final settings = NotificationSettings();

    await scheduleMealNotifications(
      settings,
      clearPendingFirst: false,
      platform: MealNotificationPlatform.ios,
      iosScheduler:
          (settings, {required clearPendingFirst, currentWeek}) async {
            iosCalls++;
          },
      androidScheduler:
          (settings, {required clearPendingFirst, currentWeek}) async {
            androidCalls++;
          },
    );

    expect(iosCalls, 1);
    expect(androidCalls, 0);
  });

  test('Web과 지원하지 않는 플랫폼에서는 어떤 예약 콜백도 호출하지 않는다', () async {
    var callCount = 0;
    Future<void> callback(
      NotificationSettings settings, {
      required bool clearPendingFirst,
      IosMealWeek? currentWeek,
    }) async {
      callCount++;
    }

    await scheduleMealNotifications(
      NotificationSettings(),
      clearPendingFirst: false,
      platform: MealNotificationPlatform.unsupported,
      iosScheduler: callback,
      androidScheduler: callback,
    );
    await cancelAllMealNotifications(
      platform: MealNotificationPlatform.unsupported,
      iosCancel: () async => callCount++,
      androidCancel: () async => callCount++,
    );

    expect(callCount, 0);
  });
}

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

WeekMeal _weekWithBreakfastMenu(DayOfWeek day) {
  final week = WeekMeal.empty();
  week[day][MealOfDay.breakfast][Cafeteria.student].add(_meal('아침'));
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
