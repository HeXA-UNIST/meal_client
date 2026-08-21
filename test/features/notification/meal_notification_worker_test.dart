import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/widget_shared_storage_io.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/notification/meal_notification_content_builder.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/features/settings/notification/notification_settings_store.dart';
import 'package:meal_client/l10n/app_localizations_en.dart';
import 'package:meal_client/l10n/app_localizations_ko.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('notification background cache refresh', () {
    test('meal cache refresh가 성공하면 info fetch 실패만으로 task를 실패시키지 않음', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async => throw Exception('info unavailable'),
        refreshWidget: () async {},
      );

      expect(result, isTrue);
    });

    test('meal cache refresh 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async => throw Exception('meal unavailable'),
        refreshInfoCache: () async {},
        refreshWidget: () async {},
      );

      expect(result, isFalse);
    });

    test('info cache write 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async =>
            throw InfoCacheWriteException(Exception('disk full')),
        refreshWidget: () async {},
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
        refreshWidget: () async {},
      );

      expect(result, isTrue);
      expect(infoStartedBeforeMealCompleted, isTrue);
    });

    test('widget refresh 실패는 task 실패로 처리', () async {
      final result = await refreshBackgroundMealAndInfoCaches(
        refreshMealCache: () async {},
        refreshInfoCache: () async {},
        refreshWidget: () async => throw Exception('widget unavailable'),
      );

      expect(result, isFalse);
    });

    test('성공한 background meal refresh는 iOS에서만 pending을 재조정한다', () async {
      var reconciliations = 0;

      final iosResult = await refreshBackgroundMealAndInfoCaches(
        platform: MealNotificationPlatform.ios,
        refreshMealCache: () async {},
        refreshInfoCache: () async {},
        refreshWidget: () async {},
        reconcileIosNotifications: () async => reconciliations++,
      );
      final androidResult = await refreshBackgroundMealAndInfoCaches(
        platform: MealNotificationPlatform.android,
        refreshMealCache: () async {},
        refreshInfoCache: () async {},
        refreshWidget: () async {},
        reconcileIosNotifications: () async => reconciliations++,
      );

      expect(iosResult, isTrue);
      expect(androidResult, isTrue);
      expect(reconciliations, 1);
    });

    test('background 재조정 중 disable되면 foreground 취소가 마지막 상태를 만든다', () async {
      final mutex = _TestMutationMutex();
      final pending = <int>{};
      final backgroundStarted = Completer<void>();
      final releaseBackground = Completer<void>();
      var persistedEnabled = true;
      var generation = 0;

      final background = reconcileBackgroundIosMealNotifications(
        mutationSection: mutex.run,
        loadSnapshot: () async => (
          settings: NotificationSettings(enabled: persistedEnabled),
          generation: generation,
          currentRevision: 'current',
          nextRevision: 'next',
        ),
        reconcile: (_) async {
          backgroundStarted.complete();
          await releaseBackground.future;
          pending.add(100000001);
        },
        cancelPending: () async => pending.clear(),
      );
      await backgroundStarted.future;

      persistedEnabled = false;
      generation++;
      final foregroundCancel = cancelAllMealNotifications(
        platform: MealNotificationPlatform.ios,
        iosCancel: () async => pending.clear(),
        mutationSection: mutex.run,
      );
      releaseBackground.complete();

      await Future.wait([background, foregroundCancel]);
      expect(pending, isEmpty);
    });

    test('disable 취소 뒤 시작한 background는 저장된 disabled 상태를 다시 적용한다', () async {
      final mutex = _TestMutationMutex();
      final pending = <int>{100000001};
      final foregroundStarted = Completer<void>();
      final releaseForeground = Completer<void>();
      const persistedEnabled = false;

      final foregroundCancel = cancelAllMealNotifications(
        platform: MealNotificationPlatform.ios,
        iosCancel: () async {
          pending.clear();
          foregroundStarted.complete();
          await releaseForeground.future;
        },
        mutationSection: mutex.run,
      );
      await foregroundStarted.future;

      final background = reconcileBackgroundIosMealNotifications(
        mutationSection: mutex.run,
        loadSnapshot: () async => (
          settings: NotificationSettings(enabled: persistedEnabled),
          generation: 1,
          currentRevision: 'current',
          nextRevision: 'next',
        ),
        reconcile: (_) async => pending.add(100000002),
        cancelPending: () async => pending.clear(),
      );
      releaseForeground.complete();

      await Future.wait([foregroundCancel, background]);
      expect(pending, isEmpty);
    });

    test('background 작업 중 설정 세대가 바뀌면 최신 설정으로 다시 재조정한다', () async {
      var generation = 0;
      var cafeterias = {Cafeteria.student};
      final reconciled = <Set<Cafeteria>>[];

      await reconcileBackgroundIosMealNotifications(
        mutationSection: (action) => action(),
        loadSnapshot: () async => (
          settings: NotificationSettings(enabled: true, cafeterias: cafeterias),
          generation: generation,
          currentRevision: 'current',
          nextRevision: 'next',
        ),
        reconcile: (settings) async {
          reconciled.add({...settings.cafeterias});
          if (reconciled.length == 1) {
            cafeterias = {Cafeteria.faculty};
            generation++;
          }
        },
      );

      expect(reconciled, [
        {Cafeteria.student},
        {Cafeteria.faculty},
      ]);
    });

    test(
      '실제 marker lock timeout 뒤에도 background가 persisted disable로 수렴한다',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'bapu-notification-lock-',
        );
        final pending = <int>{};
        final backgroundStarted = Completer<void>();
        final releaseBackground = Completer<void>();
        var enabled = true;
        var generation = 0;

        Future<void> mutationSection(Future<void> Function() action) =>
            withSharedWidgetFileLock(
              'meal-notification-pending',
              action,
              directory: directory,
            );

        try {
          final background = reconcileBackgroundIosMealNotifications(
            mutationSection: mutationSection,
            loadSnapshot: () async => (
              settings: NotificationSettings(enabled: enabled),
              generation: generation,
              currentRevision: 'current',
              nextRevision: 'next',
            ),
            reconcile: (_) async {
              backgroundStarted.complete();
              await releaseBackground.future;
              pending.add(100000001);
            },
            cancelPending: () async => pending.clear(),
          );
          await backgroundStarted.future;

          // 실제 foreground는 설정과 세대를 먼저 저장한 뒤 lock을 기다린다.
          enabled = false;
          generation++;
          await expectLater(
            mutationSection(() async => pending.clear()),
            throwsA(isA<TimeoutException>()),
          );

          releaseBackground.complete();
          await background;

          expect(pending, isEmpty);
        } finally {
          if (!releaseBackground.isCompleted) releaseBackground.complete();
          await directory.delete(recursive: true);
        }
      },
    );
  });

  group('알림 대상 주차 로딩', () {
    test('다음 주 대상은 현재 주 캐시 대신 날짜 지정 API를 사용한다', () async {
      var currentWeekLoads = 0;
      String? requestedWeekStart;
      final previousWeekMeal = WeekMeal.empty();
      previousWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory]
          .add(_mealWithMenu('지난주 월요일'));
      final nextWeekMeal = WeekMeal.empty();
      nextWeekMeal[DayOfWeek.mon][MealOfDay.breakfast][Cafeteria.dormitory].add(
        _mealWithMenu('다음주 월요일'),
      );

      final result = await loadMealForNotificationTarget(
        targetDate: DateTime.utc(2026, 7, 20),
        now: DateTime.utc(2026, 7, 19, 12, 30),
        loadCurrentWeek: () async {
          currentWeekLoads++;
          return previousWeekMeal;
        },
        loadDatedWeek: (weekStart) async {
          requestedWeekStart = weekStart;
          return nextWeekMeal;
        },
      );

      expect(result, same(nextWeekMeal));
      expect(currentWeekLoads, 0);
      expect(requestedWeekStart, '2026-07-20');
      final targetMeals = mealsForNotificationTarget(
        weekMeal: result,
        targetDate: DateTime.utc(2026, 7, 20),
        period: MealNotificationPeriod.night,
        cafeteria: Cafeteria.dormitory,
      );
      expect(mealContainsKeyword(targetMeals.single, '다음주'), isTrue);
      expect(mealContainsKeyword(targetMeals.single, '지난주'), isFalse);
    });

    test('현재 주 대상은 기존 캐시 및 갱신 경로를 사용한다', () async {
      var datedWeekLoads = 0;
      final currentWeekMeal = WeekMeal.empty();

      final result = await loadMealForNotificationTarget(
        targetDate: DateTime.utc(2026, 7, 19),
        now: DateTime.utc(2026, 7, 19, 12, 30),
        loadCurrentWeek: () async => currentWeekMeal,
        loadDatedWeek: (_) async {
          datedWeekLoads++;
          return WeekMeal.empty();
        },
      );

      expect(result, same(currentWeekMeal));
      expect(datedWeekLoads, 0);
    });

    test('지난 대상 날짜는 알림 검사 전에 건너뛴다', () {
      expect(
        isNotificationTargetInPast(
          DateTime.utc(2026, 7, 19),
          DateTime.utc(2026, 7, 20),
        ),
        isTrue,
      );
      expect(
        isNotificationTargetInPast(
          DateTime.utc(2026, 7, 20),
          DateTime.utc(2026, 7, 20, 12, 5),
        ),
        isFalse,
      );
    });
  });

  group('구버전 알림 태스크', () {
    test('대상 날짜가 없으면 검사하지 않고 다음 작업만 재예약한다', () async {
      var checkCount = 0;
      var rescheduleCount = 0;

      await handleKeywordNotificationTask(
        period: MealNotificationPeriod.night,
        targetDateInput: null,
        runCheck: (_, _) async => checkCount++,
        reschedule: (_) async => rescheduleCount++,
      );

      expect(checkCount, 0);
      expect(rescheduleCount, 1);
    });

    test('저장된 날짜가 있으면 그 날짜로 검사한 뒤 재예약한다', () async {
      DateTime? checkedTargetDate;
      var rescheduleCount = 0;

      await handleKeywordNotificationTask(
        period: MealNotificationPeriod.night,
        targetDateInput: '2026-07-20',
        runCheck: (_, targetDate) async => checkedTargetDate = targetDate,
        reschedule: (_) async => rescheduleCount++,
      );

      expect(checkedTargetDate, DateTime.utc(2026, 7, 20));
      expect(rescheduleCount, 1);
    });
  });

  group('알림 키워드 매칭', () {
    final meal = Meal(
      sections: const [
        MealSection(
          type: MealSectionType.regular,
          menu: [MealMenuItem(ko: '떡갈비', en: 'Grilled Short Rib Patties')],
        ),
        MealSection(
          type: MealSectionType.convenience,
          menu: [MealMenuItem(ko: '참치마요 덮밥')],
        ),
        MealSection(
          type: MealSectionType.special,
          menu: [MealMenuItem(ko: '특선 메뉴', en: 'Chef Special')],
        ),
        MealSection(
          type: MealSectionType.salad,
          menu: [MealMenuItem(ko: '시저 샐러드', en: 'Caesar Salad')],
        ),
      ],
    );

    test('표시 대상 섹션의 한글과 영문 메뉴를 대소문자 구분 없이 검색한다', () {
      expect(mealContainsKeyword(meal, '떡갈비'), isTrue);
      expect(mealContainsKeyword(meal, 'grilled short'), isTrue);
      expect(mealContainsKeyword(meal, '참치마요'), isTrue);
      expect(mealContainsKeyword(meal, 'chef special'), isTrue);
    });

    test('표시하지 않는 SALAD 섹션은 검색 대상에서 제외한다', () {
      expect(mealContainsKeyword(meal, '시저'), isFalse);
      expect(mealContainsKeyword(meal, 'caesar'), isFalse);
    });
  });

  group('공유 알림 설정 해석', () {
    test('저장 상태별 식당과 기숙사 메뉴 기본값을 한 경로에서 정규화한다', () async {
      final cases = <_NotificationSettingsCase>[
        (
          values: const {},
          cafeterias: const {Cafeteria.dormitory},
          dormMealTypes: const {DormMealType.korean, DormMealType.halal},
        ),
        (
          values: const {
            'settings_notification_cafeterias': ['student'],
          },
          cafeterias: const {Cafeteria.student},
          dormMealTypes: const {},
        ),
        (
          values: const {
            'settings_notification_cafeterias': ['dormitory', 'student'],
          },
          cafeterias: const {Cafeteria.dormitory, Cafeteria.student},
          dormMealTypes: const {DormMealType.korean, DormMealType.halal},
        ),
        (
          values: const {
            'settings_notification_cafeterias': ['faculty'],
            'settings_notification_dorm_meal_types': ['halal'],
          },
          cafeterias: const {Cafeteria.dormitory, Cafeteria.faculty},
          dormMealTypes: const {DormMealType.halal},
        ),
      ];

      for (final scenario in cases) {
        SharedPreferences.setMockInitialValues(scenario.values);
        final prefs = await SharedPreferences.getInstance();
        final delivery = normalizeNotificationDeliverySettings(
          loadNotificationSettings(prefs),
          keywordFilterEnabled: false,
        );

        expect(delivery.cafeterias, scenario.cafeterias);
        expect(delivery.dormMealTypes, scenario.dormMealTypes);
      }
    });

    test('레거시 값을 마이그레이션하고 Release 키워드 게이트를 공통 적용한다', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_keyword': '  돈까스  ',
        'settings_notification_time': '8:0',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = loadNotificationSettings(prefs);

      expect(
        settings.alertTimeOf(MealNotificationPeriod.morning),
        const TimeOfDay(hour: 8, minute: 0),
      );
      expect(prefs.getString('settings_notification_time'), isNull);
      expect(
        normalizeNotificationDeliverySettings(
          settings,
          keywordFilterEnabled: true,
        ).keywords,
        ['돈까스'],
      );
      expect(
        normalizeNotificationDeliverySettings(
          settings,
          keywordFilterEnabled: false,
        ).keywords,
        isEmpty,
      );
    });
  });

  group('공유 알림 콘텐츠 생성', () {
    test('식당별 한국어 전체 메뉴를 고유 ID와 한 줄 본문으로 만든다', () {
      final weekMeal = _notificationWeekMeal();
      final contents = buildMealNotificationContents(
        weekMeal: weekMeal,
        targetDate: DateTime.utc(2026, 7, 20),
        period: MealNotificationPeriod.lunch,
        settings: NotificationDeliverySettings(
          cafeterias: Cafeteria.values.toSet(),
          dormMealTypes: DormMealType.values.toSet(),
          keywords: const [],
        ),
        l10n: AppLocalizationsKo(),
      );

      expect(contents.map((content) => content.id), [1, 2, 3, 4]);
      expect(contents.map((content) => content.title), [
        '기숙사 식당(한식) 점심 메뉴를 알려드려요.',
        '기숙사 식당(할랄) 점심 메뉴를 알려드려요.',
        '학생 식당 점심 메뉴를 알려드려요.',
        '교직원 식당 점심 메뉴를 알려드려요.',
      ]);
      expect(contents.map((content) => content.body), [
        '김치찌개 / 공기밥',
        '할랄 치킨',
        '학생 메뉴',
        '교직원 메뉴',
      ]);
    });

    test('영문 메뉴와 한국어 fallback을 사용하고 일반 기숙사 Meal은 제외한다', () {
      final contents = buildMealNotificationContents(
        weekMeal: _notificationWeekMeal(),
        targetDate: DateTime.utc(2026, 7, 20),
        period: MealNotificationPeriod.lunch,
        settings: NotificationDeliverySettings(
          cafeterias: const {Cafeteria.dormitory},
          dormMealTypes: const {DormMealType.korean},
          keywords: const [],
        ),
        l10n: AppLocalizationsEn(),
      );

      expect(contents, hasLength(1));
      expect(contents.single.id, 1);
      expect(contents.single.title, 'Dormitory (Korean) Lunch Menu');
      expect(contents.single.body, 'Kimchi Stew / 공기밥');
    });
  });
}

class _TestMutationMutex {
  Future<void> _queue = Future.value();

  Future<void> run(Future<void> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }
}

typedef _NotificationSettingsCase = ({
  Map<String, Object> values,
  Set<Cafeteria> cafeterias,
  Set<DormMealType> dormMealTypes,
});

Meal _mealWithMenu(String menu) {
  return Meal(
    sections: [
      MealSection(
        type: MealSectionType.regular,
        menu: [MealMenuItem(ko: menu)],
      ),
    ],
  );
}

WeekMeal _notificationWeekMeal() {
  final weekMeal = WeekMeal.empty();
  final lunch = weekMeal[DayOfWeek.mon][MealOfDay.lunch];
  lunch[Cafeteria.dormitory].addAll([
    const KoreanMeal(
      sections: [
        MealSection(
          type: MealSectionType.regular,
          menu: [
            MealMenuItem(ko: '김치찌개', en: 'Kimchi Stew'),
            MealMenuItem(ko: '공기밥'),
          ],
        ),
        MealSection(
          type: MealSectionType.salad,
          menu: [MealMenuItem(ko: '샐러드', en: 'Salad')],
        ),
      ],
    ),
    const HalalMeal(
      sections: [
        MealSection(
          type: MealSectionType.regular,
          menu: [MealMenuItem(ko: '할랄 치킨', en: 'Halal Chicken')],
        ),
      ],
    ),
    const Meal(
      sections: [
        MealSection(
          type: MealSectionType.regular,
          menu: [MealMenuItem(ko: '기타 메뉴', en: 'Other Menu')],
        ),
      ],
    ),
  ]);
  lunch[Cafeteria.student].add(_mealWithMenu('학생 메뉴'));
  lunch[Cafeteria.faculty].add(_mealWithMenu('교직원 메뉴'));
  return weekMeal;
}
