import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/settings/allergy/allergy_settings.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AllergySettings', () {
    test('기본값: enabledIds가 비어 있음', () {
      final s = AllergySettings();
      expect(s.enabledIds, isEmpty);
    });

    test('toggle — 없는 ID 추가', () {
      final s = AllergySettings();
      final next = s.toggle(1);
      expect(next.enabledIds, contains(1));
    });

    test('toggle — 있는 ID 제거', () {
      final s = AllergySettings(enabledIds: {1, 2});
      final next = s.toggle(1);
      expect(next.enabledIds, isNot(contains(1)));
      expect(next.enabledIds, contains(2));
    });

    test('reset — enabledIds가 비어 있음', () {
      final s = AllergySettings(enabledIds: {1, 5, 9});
      expect(s.reset().enabledIds, isEmpty);
    });

    test('enabledIds — 불변 Set 반환', () {
      final s = AllergySettings(enabledIds: {1, 2});
      expect(() => (s.enabledIds as dynamic).add(3), throwsUnsupportedError);
    });
  });

  group('NotificationSettings', () {
    test('기본값', () {
      final s = NotificationSettings();
      expect(s.enabled, isFalse);
      expect(s.keywords, isEmpty);
      expect(s.alertTimes, isEmpty);
      expect(s.activePeriods, isEmpty);
      // cafeterias는 학생·교직원만 담당하고 기본값은 비어 있다.
      // 기숙사 식당의 알림 대상 여부는 dormMealTypes로만 판단한다.
      expect(s.cafeterias, isEmpty);
      expect(
        s.dormMealTypes,
        equals({DormMealType.korean, DormMealType.halal}),
      );
      expect(s.activeCafeterias, equals({Cafeteria.dormitory}));
    });

    test('activePeriods — 시각 설정된 시간대만 포함', () {
      final s = NotificationSettings(
        alertTimes: {
          MealNotificationPeriod.morning: const TimeOfDay(hour: 8, minute: 0),
          MealNotificationPeriod.dinner: null,
        },
      );
      expect(s.activePeriods, equals([MealNotificationPeriod.morning]));
      expect(s.isPeriodEnabled(MealNotificationPeriod.morning), isTrue);
      expect(s.isPeriodEnabled(MealNotificationPeriod.dinner), isFalse);
    });

    test('copyWith — enabled만 변경', () {
      final s = NotificationSettings();
      final next = s.copyWith(enabled: true);
      expect(next.enabled, isTrue);
      expect(next.keywords, isEmpty);
    });

    test('reset — 기본값으로 초기화', () {
      final s = NotificationSettings(
        enabled: true,
        keywords: ['돈까스', '국'],
        alertTimes: {
          MealNotificationPeriod.lunch: const TimeOfDay(hour: 11, minute: 0),
        },
      );
      final r = s.reset();
      expect(r.enabled, isFalse);
      expect(r.keywords, isEmpty);
      expect(r.alertTimes, isEmpty);
    });

    test('keywords — 불변 List 반환', () {
      final s = NotificationSettings(keywords: ['돈까스']);
      expect(() => (s.keywords as dynamic).add('국'), throwsUnsupportedError);
    });

    test('alertTimes — 불변 Map 반환', () {
      final s = NotificationSettings(
        alertTimes: {
          MealNotificationPeriod.morning: const TimeOfDay(hour: 8, minute: 0),
        },
      );
      expect(
        () => (s.alertTimes as dynamic)[MealNotificationPeriod.lunch] = null,
        throwsUnsupportedError,
      );
    });

    test('cafeterias — 불변 Set 반환', () {
      final s = NotificationSettings();
      expect(
        () => (s.cafeterias as dynamic).add(Cafeteria.student),
        throwsUnsupportedError,
      );
    });
  });

  group('MealAlertPeriod', () {
    test('아침 슬롯: 07:30~08:30 15분 간격 5개', () {
      final slots = MealNotificationPeriod.morning.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 7, minute: 30));
      expect(slots.last, const TimeOfDay(hour: 8, minute: 30));
    });

    test('점심 슬롯: 10:30~11:30 15분 간격 5개', () {
      final slots = MealNotificationPeriod.lunch.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 10, minute: 30));
      expect(slots.last, const TimeOfDay(hour: 11, minute: 30));
    });

    test('저녁 슬롯: 16:30~17:30 15분 간격 5개', () {
      final slots = MealNotificationPeriod.dinner.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 16, minute: 30));
      expect(slots.last, const TimeOfDay(hour: 17, minute: 30));
    });

    test('밤 슬롯: 21:00~22:00 15분 간격 5개', () {
      final slots = MealNotificationPeriod.night.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 21, minute: 0));
      expect(slots.last, const TimeOfDay(hour: 22, minute: 0));
    });

    test('night 시간대는 내일 아침 breakfast 검사', () {
      expect(MealNotificationPeriod.night.tomorrow, isTrue);
      expect(MealNotificationPeriod.night.mealOfDay, MealOfDay.breakfast);
    });

    test('오늘 시간대는 tomorrow=false', () {
      expect(MealNotificationPeriod.morning.tomorrow, isFalse);
      expect(MealNotificationPeriod.lunch.tomorrow, isFalse);
      expect(MealNotificationPeriod.dinner.tomorrow, isFalse);
    });
  });
  group('AppSettings', () {
    late List<AppSettings> settingsToDispose;

    AppSettings createSettings(SharedPreferences prefs) {
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {},
          cancel: () async {},
        ),
        notificationPermissionRequester: () async => true,
      );
      settingsToDispose.add(settings);
      return settings;
    }

    setUp(() {
      settingsToDispose = [];
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      for (final settings in settingsToDispose) {
        settings.dispose();
      }
    });

    test('기본값으로 초기화', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      expect(settings.allergy.enabledIds, isEmpty);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.notification.enabled, isFalse);
    });

    test('toggleAllergen — 추가 및 제거', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.toggleAllergen(1);
      expect(settings.allergy.enabledIds, contains(1));
      settings.toggleAllergen(1);
      expect(settings.allergy.enabledIds, isNot(contains(1)));
    });

    test('toggleAllergen — SharedPreferences에 저장 후 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.toggleAllergen(3);
      settings.toggleAllergen(7);
      final settings2 = createSettings(prefs);
      expect(settings2.allergy.enabledIds, containsAll([3, 7]));
    });

    test('toggleAllergen — notifyListeners 호출', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      var notified = false;
      settings.addListener(() => notified = true);
      settings.toggleAllergen(5);
      expect(notified, isTrue);
    });

    test('setThemeMode — 저장 및 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.setThemeMode(ThemeMode.dark);
      final settings2 = createSettings(prefs);
      expect(settings2.themeMode, ThemeMode.dark);
    });

    test('setNotificationEnabled — 저장 및 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      await settings.setNotificationEnabled(true);
      final settings2 = createSettings(prefs);
      expect(settings2.notification.enabled, isTrue);
    });

    test('알림 권한 거부는 활성화하지 않고 관찰 가능한 상태로 남긴다', () async {
      final prefs = await SharedPreferences.getInstance();
      var requestCount = 0;
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {},
          cancel: () async {},
        ),
        notificationPermissionRequester: () async {
          requestCount++;
          return false;
        },
      );
      settingsToDispose.add(settings);

      expect(await settings.setNotificationEnabled(true), isFalse);
      expect(requestCount, 1);
      expect(settings.notification.enabled, isFalse);
      expect(
        settings.notificationAuthorizationStatus,
        MealNotificationAuthorizationStatus.notAuthorized,
      );
    });

    test('알림 콘텐츠에 영향을 주는 모든 설정 변경은 예약 갱신을 요청한다', () async {
      final prefs = await SharedPreferences.getInstance();
      var scheduleCount = 0;
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          debounce: Duration.zero,
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {
                scheduleCount++;
              },
          cancel: () async {},
        ),
        notificationPermissionRequester: () async => true,
      );
      settingsToDispose.add(settings);

      await settings.setNotificationEnabled(true);
      await Future<void>.delayed(Duration.zero);
      final countAfterEnable = scheduleCount;

      settings.addNotificationKeyword('국');
      await _waitUntil(() => scheduleCount == countAfterEnable + 1);
      settings.removeNotificationKeyword('국');
      await _waitUntil(() => scheduleCount == countAfterEnable + 2);
      settings.setNotificationCafeterias({Cafeteria.student});
      await _waitUntil(() => scheduleCount == countAfterEnable + 3);
      settings.setNotificationDormMealTypes({DormMealType.korean});
      await _waitUntil(() => scheduleCount == countAfterEnable + 4);

      expect(scheduleCount, countAfterEnable + 4);
    });

    test('master disable과 reset은 예약과 관찰 중인 권한 상태를 함께 지운다', () async {
      final prefs = await SharedPreferences.getInstance();
      var cancelCount = 0;
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          debounce: Duration.zero,
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {},
          cancel: () async => cancelCount++,
        ),
        notificationPermissionRequester: () async => true,
      );
      settingsToDispose.add(settings);

      await settings.setNotificationEnabled(true);
      await settings.setNotificationEnabled(false);
      await settings.setNotificationEnabled(true);
      settings.resetAll();
      await Future<void>.delayed(Duration.zero);

      expect(cancelCount, 2);
      expect(settings.notification.enabled, isFalse);
      expect(settings.notificationAuthorizationStatus, isNull);
    });

    test('비동기 권한 조회 결과는 알림을 끈 뒤 상태를 되살리지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final status = Completer<MealNotificationAuthorizationStatus>();
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {},
          cancel: () async {},
        ),
        notificationPermissionRequester: () async => true,
        notificationAuthorizationStatusReader: () => status.future,
      );
      settingsToDispose.add(settings);

      final refresh = settings.refreshNotificationAuthorizationStatus();
      await settings.setNotificationEnabled(false);
      status.complete(MealNotificationAuthorizationStatus.notAuthorized);
      await refresh;

      expect(settings.notificationAuthorizationStatus, isNull);
    });

    test('iOS resume은 매번 재조정하지만 1시간 이내 foreground fetch는 생략한다', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 8, 20, 3);
      VoidCallback? onResume;
      var scheduleCount = 0;
      var refreshCount = 0;
      var currentRevision = (
        rawMeal: _rawWeek('2026-08-17'),
        updatedAt: now.subtract(const Duration(minutes: 10)),
      );
      final settings = AppSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.ios,
        resumeListenerRegistrar: (listener) {
          onResume = listener;
          return () {};
        },
        clock: () => now,
        mealCacheRevisionSnapshotReader: () async =>
            (current: currentRevision, next: null),
        foregroundMealRefresher: (now, waitForNextWeekPrefetch) async {
          refreshCount++;
          currentRevision = (
            rawMeal: '${_rawWeek('2026-08-17')} ',
            updatedAt: now,
          );
        },
        notificationAuthorizationStatusReader: () async =>
            MealNotificationAuthorizationStatus.enabled,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {
                scheduleCount++;
              },
          cancel: () async {},
        ),
      );
      settingsToDispose.add(settings);

      onResume!();
      await _waitUntil(() => scheduleCount == 1);
      onResume!();
      await _waitUntil(() => scheduleCount == 2);

      expect(refreshCount, isZero);

      currentRevision = (
        rawMeal: currentRevision.rawMeal,
        updatedAt: now.subtract(const Duration(hours: 2)),
      );
      onResume!();
      await _waitUntil(() => refreshCount == 1);

      expect(refreshCount, 1);
    });

    test('KST 일요일 next-week top-up은 1시간 제한을 무시하고 중복 실행하지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 8, 23, 3); // KST 일요일 정오
      VoidCallback? onResume;
      var refreshCount = 0;
      var waitForNextWeek = false;
      var scheduleCount = 0;
      MealCacheRevisionSnapshot revisions = (
        current: (rawMeal: _rawWeek('2026-08-17'), updatedAt: now),
        next: (
          rawMeal: _rawWeek('2026-08-24'),
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
      );
      final refreshCompleted = Completer<void>();
      final settings = AppSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.ios,
        resumeListenerRegistrar: (listener) {
          onResume = listener;
          return () {};
        },
        clock: () => now,
        mealCacheRevisionSnapshotReader: () async => revisions,
        foregroundMealRefresher: (instant, wait) async {
          refreshCount++;
          waitForNextWeek = wait;
          await refreshCompleted.future;
        },
        notificationAuthorizationStatusReader: () async =>
            MealNotificationAuthorizationStatus.enabled,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {
                scheduleCount++;
              },
          cancel: () async {},
        ),
      );
      settingsToDispose.add(settings);

      onResume!();
      await _waitUntil(() => refreshCount == 1);
      revisions = (
        current: (rawMeal: _rawWeek('2026-08-17'), updatedAt: now),
        next: (rawMeal: '${_rawWeek('2026-08-24')} ', updatedAt: now),
      );
      refreshCompleted.complete();
      await _waitUntil(() => scheduleCount == 2);

      expect(refreshCount, 1);
      expect(waitForNextWeek, isTrue);
      expect(scheduleCount, 2);
    });

    test('dispose 중인 iOS resume 권한 조회는 상태와 예약을 변경하지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final authorization = Completer<MealNotificationAuthorizationStatus>();
      VoidCallback? onResume;
      var scheduleCount = 0;
      final settings = AppSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.ios,
        resumeListenerRegistrar: (listener) {
          onResume = listener;
          return () {};
        },
        notificationAuthorizationStatusReader: () => authorization.future,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule:
              (
                settings, {
                required clearPendingFirst,
                required isCurrent,
                currentWeek,
              }) async {
                scheduleCount++;
              },
          cancel: () async {},
        ),
      );

      onResume!();
      settings.dispose();
      authorization.complete(MealNotificationAuthorizationStatus.enabled);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(scheduleCount, isZero);
      expect(settings.notificationAuthorizationStatus, isNull);
    });

    test('addNotificationKeyword — 추가 및 중복 방지', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.addNotificationKeyword('떡갈비');
      settings.addNotificationKeyword('국');
      settings.addNotificationKeyword('떡갈비'); // 중복
      expect(settings.notification.keywords, equals(['떡갈비', '국']));
    });

    test('addNotificationKeyword — 빈 문자열·공백 무시', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.addNotificationKeyword('');
      settings.addNotificationKeyword('   ');
      expect(settings.notification.keywords, isEmpty);
    });

    test('removeNotificationKeyword — 제거', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.addNotificationKeyword('떡갈비');
      settings.addNotificationKeyword('국');
      settings.removeNotificationKeyword('떡갈비');
      expect(settings.notification.keywords, equals(['국']));
    });

    test('addNotificationKeyword — SharedPreferences 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.addNotificationKeyword('떡갈비');
      settings.addNotificationKeyword('국');
      final settings2 = createSettings(prefs);
      expect(settings2.notification.keywords, equals(['떡갈비', '국']));
    });

    test('구버전 단일 키워드 마이그레이션', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_keyword': '돈까스',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      expect(settings.notification.keywords, equals(['돈까스']));
      // 새 키로 마이그레이션됐는지 확인
      expect(
        prefs.getStringList('settings_notification_keywords'),
        equals(['돈까스']),
      );
      // 구 키는 삭제됐는지 확인
      expect(prefs.getString('settings_notification_keyword'), isNull);
    });

    test('setPeriodAlertTime — 시각 설정 후 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.setPeriodAlertTime(
        MealNotificationPeriod.lunch,
        const TimeOfDay(hour: 11, minute: 0),
      );
      expect(
        settings.notification.alertTimeOf(MealNotificationPeriod.lunch),
        const TimeOfDay(hour: 11, minute: 0),
      );
      final settings2 = createSettings(prefs);
      expect(
        settings2.notification.alertTimeOf(MealNotificationPeriod.lunch),
        const TimeOfDay(hour: 11, minute: 0),
      );
    });

    test('setPeriodAlertTime(null) — 시각 제거', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.setPeriodAlertTime(
        MealNotificationPeriod.lunch,
        const TimeOfDay(hour: 11, minute: 0),
      );
      settings.setPeriodAlertTime(MealNotificationPeriod.lunch, null);
      expect(
        settings.notification.alertTimeOf(MealNotificationPeriod.lunch),
        isNull,
      );
      expect(settings.notification.activePeriods, isEmpty);
    });

    test('시간대를 꺼도 마지막 선택 시각은 유지된다 (displayTime)', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      const picked = TimeOfDay(hour: 11, minute: 15);
      settings.setPeriodAlertTime(MealNotificationPeriod.lunch, picked);
      // 끄면 alertTime은 사라지지만 displayTime은 이전 선택값 유지
      settings.setPeriodAlertTime(MealNotificationPeriod.lunch, null);
      expect(
        settings.notification.isPeriodEnabled(MealNotificationPeriod.lunch),
        isFalse,
      );
      expect(
        settings.notification.displayTimeOf(MealNotificationPeriod.lunch),
        picked,
      );

      // 재로드해도 기억값이 유지된다
      final settings2 = createSettings(prefs);
      expect(
        settings2.notification.isPeriodEnabled(MealNotificationPeriod.lunch),
        isFalse,
      );
      expect(
        settings2.notification.displayTimeOf(MealNotificationPeriod.lunch),
        picked,
      );
    });

    test('displayTime — 한 번도 설정 안 하면 기본 슬롯', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      expect(
        settings.notification.displayTimeOf(MealNotificationPeriod.lunch),
        MealNotificationPeriod.lunch.defaultSlot,
      );
    });

    test('알림 요일 — 기본값은 모든 요일', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      expect(settings.notification.days, equals(DayOfWeek.values.toSet()));
      for (final d in DayOfWeek.values) {
        expect(settings.notification.isDayEnabled(d), isTrue);
      }
    });

    test('setNotificationDays — 저장 후 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      final weekdaysOnly = {
        DayOfWeek.mon,
        DayOfWeek.tue,
        DayOfWeek.wed,
        DayOfWeek.thu,
        DayOfWeek.fri,
      };
      settings.setNotificationDays(weekdaysOnly);
      expect(settings.notification.isDayEnabled(DayOfWeek.sat), isFalse);
      expect(settings.notification.isDayEnabled(DayOfWeek.mon), isTrue);

      final settings2 = createSettings(prefs);
      expect(settings2.notification.days, equals(weekdaysOnly));
    });

    test('로드: 유효하지 않은 슬롯은 무시', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_period_time_lunch': '11:07', // 15분 슬롯 아님
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      expect(settings.notification.activePeriods, isEmpty);
    });

    test('구버전 단일 알림 시각(08:00) 마이그레이션 → 아침', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_time': '8:0',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      expect(
        settings.notification.alertTimeOf(MealNotificationPeriod.morning),
        const TimeOfDay(hour: 8, minute: 0),
      );
      // 구 키는 삭제
      expect(prefs.getString('settings_notification_time'), isNull);
    });

    test('resetAll — 모든 값이 기본값으로', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      settings.toggleAllergen(1);
      settings.setThemeMode(ThemeMode.dark);
      await settings.setNotificationEnabled(true);
      settings.resetAll();
      expect(settings.allergy.enabledIds, isEmpty);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.notification.enabled, isFalse);
    });
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('비동기 조건이 완료되지 않았습니다.');
}

String _rawWeek(String startDate) =>
    '{"week":{"startDate":"$startDate","isCurrentWeek":true},"data":[]}';
