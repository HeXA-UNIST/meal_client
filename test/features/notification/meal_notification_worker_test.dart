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
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:meal_client/features/settings/notification/notification_settings_store.dart';
import 'package:meal_client/l10n/app_localizations_en.dart';
import 'package:meal_client/l10n/app_localizations_ko.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('성공한 background refresh는 iOS에서만 pending을 재조정한다', () async {
    var reconciliations = 0;
    for (final platform in MealNotificationPlatform.values) {
      final result = await refreshBackgroundMealAndInfoCaches(
        platform: platform,
        refreshMealCache: () async {},
        refreshInfoCache: () async {},
        refreshWidget: () async {},
        reconcileIosNotifications: () async => reconciliations++,
      );
      expect(result, isTrue);
    }
    expect(reconciliations, 1);
  });

  test('background refresh는 필수 단계 실패만 task 실패로 반환한다', () async {
    final cases =
        <
          ({
            Future<void> Function() meal,
            Future<void> Function() info,
            Future<void> Function() widget,
            bool expected,
          })
        >[
          (
            meal: () async => throw Exception('meal unavailable'),
            info: () async {},
            widget: () async {},
            expected: false,
          ),
          (
            meal: () async {},
            info: () async => throw Exception('info unavailable'),
            widget: () async {},
            expected: true,
          ),
          (
            meal: () async {},
            info: () async =>
                throw InfoCacheWriteException(Exception('disk full')),
            widget: () async {},
            expected: false,
          ),
          (
            meal: () async {},
            info: () async {},
            widget: () async => throw Exception('widget unavailable'),
            expected: false,
          ),
        ];

    for (final scenario in cases) {
      expect(
        await refreshBackgroundMealAndInfoCaches(
          refreshMealCache: scenario.meal,
          refreshInfoCache: scenario.info,
          refreshWidget: scenario.widget,
        ),
        scenario.expected,
      );
    }
  });

  test('background는 설정 세대가 바뀌면 안정된 최신 스냅샷으로 수렴한다', () async {
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

  test('긴 cross-isolate lock 뒤에도 persisted disable로 수렴한다', () async {
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
  });

  test('공유 설정은 Release 키워드 게이트와 현재 기본값을 한 번만 적용한다', () async {
    SharedPreferences.setMockInitialValues({
      'settings_notification_keywords': ['  돈까스  '],
      'settings_notification_period_time_morning': '8:0',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = loadNotificationSettings(prefs);

    expect(
      settings.alertTimeOf(MealNotificationPeriod.morning),
      const TimeOfDay(hour: 8, minute: 0),
    );
    expect(
      normalizeNotificationDeliverySettings(
        settings,
        keywordFilterEnabled: true,
      ).keywords,
      ['돈까스'],
    );
    final releaseSettings = normalizeNotificationDeliverySettings(
      settings,
      keywordFilterEnabled: false,
    );
    expect(releaseSettings.keywords, isEmpty);
    expect(releaseSettings.cafeterias, {Cafeteria.dormitory});
    expect(releaseSettings.dormMealTypes, DormMealType.values.toSet());
  });

  test('식당별 전체 메뉴를 한국어와 영어로 동일한 고유 그룹에 생성한다', () {
    final settings = NotificationDeliverySettings(
      cafeterias: Cafeteria.values.toSet(),
      dormMealTypes: DormMealType.values.toSet(),
      keywords: const [],
    );
    final weekMeal = _notificationWeekMeal();

    final korean = buildMealNotificationContents(
      weekMeal: weekMeal,
      targetDate: DateTime.utc(2026, 7, 20),
      period: MealNotificationPeriod.lunch,
      settings: settings,
      l10n: AppLocalizationsKo(),
    );
    final english = buildMealNotificationContents(
      weekMeal: weekMeal,
      targetDate: DateTime.utc(2026, 7, 20),
      period: MealNotificationPeriod.lunch,
      settings: settings,
      l10n: AppLocalizationsEn(),
    );

    expect(korean.map((content) => content.id), [1, 2, 3, 4]);
    expect(korean.map((content) => content.title), [
      '기숙사 식당(한식) 점심 메뉴를 알려드려요.',
      '기숙사 식당(할랄) 점심 메뉴를 알려드려요.',
      '학생 식당 점심 메뉴를 알려드려요.',
      '교직원 식당 점심 메뉴를 알려드려요.',
    ]);
    expect(korean.map((content) => content.body), [
      '김치찌개 / 공기밥',
      '할랄 치킨',
      '학생 메뉴',
      '교직원 메뉴',
    ]);
    expect(english.map((content) => content.id), [1, 2, 3, 4]);
    expect(english.first.title, 'Dormitory (Korean) Lunch Menu');
    expect(english.first.body, 'Kimchi Stew / 공기밥');
  });
}

Meal _mealWithMenu(String menu) => Meal(
  sections: [
    MealSection(
      type: MealSectionType.regular,
      menu: [MealMenuItem(ko: menu)],
    ),
  ],
);

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
  ]);
  lunch[Cafeteria.student].add(_mealWithMenu('학생 메뉴'));
  lunch[Cafeteria.faculty].add(_mealWithMenu('교직원 메뉴'));
  return weekMeal;
}
