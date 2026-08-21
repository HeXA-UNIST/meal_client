import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
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
    test('기본 알림 대상과 활성 시간대를 불변 스냅샷으로 보관한다', () {
      final s = NotificationSettings();
      expect(s.enabled, isFalse);
      expect(s.activePeriods, isEmpty);
      expect(s.activeCafeterias, equals({Cafeteria.dormitory}));
      expect(
        () => (s.dormMealTypes as dynamic).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => (s.cafeterias as dynamic).add(Cafeteria.student),
        throwsUnsupportedError,
      );
    });
  });

  test('플랫폼 locale 목록이 비어 있으면 알림은 한국어를 사용한다', () {
    expect(resolveNotificationLocalizations(const []).localeName, 'ko');
  });

  group('MealNotificationPeriod', () {
    test('각 시간대는 15분 간격 선택지와 올바른 대상 식사를 갖는다', () {
      for (final period in MealNotificationPeriod.values) {
        expect(period.allSlots, hasLength(5));
      }
      expect(
        MealNotificationPeriod.morning.allSlots.first,
        const TimeOfDay(hour: 7, minute: 30),
      );
      expect(
        MealNotificationPeriod.night.allSlots.last,
        const TimeOfDay(hour: 22, minute: 0),
      );
      expect(MealNotificationPeriod.night.tomorrow, isTrue);
      expect(MealNotificationPeriod.night.mealOfDay, MealOfDay.breakfast);
    });
  });
  group('AppSettings', () {
    late List<AppSettings> settingsToDispose;

    AppSettings createSettings(SharedPreferences prefs) {
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (settings, {required isCurrent}) async {},
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

    test('알림 권한 거부와 시스템 설정에서의 복구를 관찰한다', () async {
      final prefs = await SharedPreferences.getInstance();
      var requestCount = 0;
      var authorization = MealNotificationAuthorizationStatus.notAuthorized;
      VoidCallback? onResume;
      final settings = AppSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.ios,
        resumeListenerRegistrar: (listener) {
          onResume = listener;
          return () {};
        },
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (settings, {required isCurrent}) async {},
          cancel: () async {},
        ),
        notificationPermissionRequester: () async {
          requestCount++;
          return false;
        },
        notificationAuthorizationStatusReader: () async => authorization,
      );
      settingsToDispose.add(settings);

      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.permissionDenied,
      );
      expect(requestCount, 1);
      expect(settings.notification.enabled, isFalse);
      expect(
        settings.notificationAuthorizationStatus,
        MealNotificationAuthorizationStatus.notAuthorized,
      );

      authorization = MealNotificationAuthorizationStatus.enabled;
      onResume!();
      await _waitUntil(
        () =>
            settings.notificationAuthorizationStatus ==
            MealNotificationAuthorizationStatus.enabled,
      );
    });

    test('reset 직후 활성화해도 저장과 예약이 최신 상태로 수렴한다', () async {
      final prefs = await SharedPreferences.getInstance();
      var cancelCount = 0;
      var scheduledEnabled = false;
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          debounce: Duration.zero,
          schedule: (settings, {required isCurrent}) async {
            scheduledEnabled = settings.enabled;
          },
          cancel: () async => cancelCount++,
        ),
        notificationPermissionRequester: () async => true,
      );
      settingsToDispose.add(settings);

      settings.resetAll();
      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.enabled,
      );

      expect(cancelCount, 1);
      expect(scheduledEnabled, isTrue);
      expect(settings.notification.enabled, isTrue);
      expect(prefs.getBool(StorageKeys.notificationEnabled), isTrue);
    });

    test('알림 저장 실패는 인메모리 설정을 이전 스냅샷으로 돌린다', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (settings, {required isCurrent}) async {},
          cancel: () async {},
        ),
        notificationPermissionRequester: () async => true,
        notificationPersistenceRunner: (_) async => false,
      );
      settingsToDispose.add(settings);

      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.failed,
      );

      expect(settings.notification.enabled, isFalse);
      expect(settings.notificationAuthorizationStatus, isNull);
      expect(settings.notificationSyncFailed, isTrue);
      expect(prefs.getBool(StorageKeys.notificationEnabled), isNull);

      final observedDays = <Set<DayOfWeek>>[];
      final rollbackPublished = Completer<void>();
      settings.addListener(() {
        observedDays.add({...settings.notification.days});
        if (observedDays.length == 2 && !rollbackPublished.isCompleted) {
          rollbackPublished.complete();
        }
      });

      settings.setNotificationDays({DayOfWeek.fri});
      await rollbackPublished.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      expect(observedDays, [
        {DayOfWeek.fri},
        DayOfWeek.values.toSet(),
      ]);
    });

    test('첫 활성화 예약이 일부 실패하면 pending을 정리하고 꺼진 상태로 돌린다', () async {
      final prefs = await SharedPreferences.getInstance();
      var cancelCount = 0;
      final settings = AppSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.android,
        resumeListenerRegistrar: (_) => () {},
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (settings, {required isCurrent}) async {
            throw StateError('partial schedule failed');
          },
          cancel: () async => cancelCount++,
        ),
        notificationPermissionRequester: () async => true,
      );
      settingsToDispose.add(settings);

      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.failed,
      );

      expect(settings.notification.enabled, isFalse);
      expect(settings.notificationSyncFailed, isTrue);
      expect(cancelCount, 1);
    });

    test('느린 권한 조회가 이후 알림 설정 변경을 덮어쓰지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.notificationEnabled: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final authorization = Completer<MealNotificationAuthorizationStatus>();
      final settings = AppSettings(
        prefs,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (settings, {required isCurrent}) async {},
          cancel: () async {},
        ),
        notificationAuthorizationStatusReader: () => authorization.future,
      );
      settingsToDispose.add(settings);

      final refresh = settings.refreshNotificationAuthorizationStatus();
      await settings.setNotificationEnabled(false);
      authorization.complete(MealNotificationAuthorizationStatus.notAuthorized);
      await refresh;

      expect(settings.notification.enabled, isFalse);
      expect(settings.notificationAuthorizationStatus, isNull);
    });

    test('후속 예약 실패는 설정을 유지하고 다시 시도하면 오류를 지운다', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.notificationEnabled: true,
      });
      final prefs = await SharedPreferences.getInstance();
      var shouldFail = true;
      final settings = AppSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.android,
        resumeListenerRegistrar: (_) => () {},
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          debounce: Duration.zero,
          schedule: (settings, {required isCurrent}) async {
            if (shouldFail) throw StateError('schedule failed');
          },
          cancel: () async {},
        ),
      );
      settingsToDispose.add(settings);

      settings.setNotificationDays({DayOfWeek.fri});
      await _waitUntil(() => settings.notificationSyncFailed);

      expect(settings.notification.days, {DayOfWeek.fri});
      expect(prefs.getStringList(StorageKeys.notificationDays), ['fri']);

      shouldFail = false;
      expect(await settings.retryNotificationSync(), isTrue);
      expect(settings.notificationSyncFailed, isFalse);
    });

    test('Android resume은 매번 재조정하지만 1시간 이내 foreground fetch는 생략한다', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_enabled': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.utc(2026, 8, 20, 3);
      VoidCallback? onResume;
      var scheduleCount = 0;
      var refreshCount = 0;
      var authorization = MealNotificationAuthorizationStatus.enabled;
      var currentRevision = (
        rawMeal: _rawWeek('2026-08-17'),
        updatedAt: now.subtract(const Duration(minutes: 10)),
      );
      final settings = AppSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.android,
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
        notificationAuthorizationStatusReader: () async => authorization,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (settings, {required isCurrent}) async {
            scheduleCount++;
          },
          cancel: () async {},
        ),
      );
      settingsToDispose.add(settings);

      onResume!();
      await _waitUntil(() => scheduleCount == 1);
      expect(
        settings.notificationAuthorizationStatus,
        MealNotificationAuthorizationStatus.enabled,
      );
      authorization = MealNotificationAuthorizationStatus.notAuthorized;
      onResume!();
      await _waitUntil(() => scheduleCount == 2);
      expect(
        settings.notificationAuthorizationStatus,
        MealNotificationAuthorizationStatus.notAuthorized,
      );

      expect(refreshCount, isZero);

      authorization = MealNotificationAuthorizationStatus.enabled;
      currentRevision = (
        rawMeal: currentRevision.rawMeal,
        updatedAt: now.subtract(const Duration(hours: 2)),
      );
      onResume!();
      await _waitUntil(() => refreshCount == 1);

      expect(refreshCount, 1);
      expect(
        settings.notificationAuthorizationStatus,
        MealNotificationAuthorizationStatus.enabled,
      );
    });

    test('KST 일요일 next-week top-up은 1시간 제한을 무시하고 완료 후 재조정한다', () async {
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
        notificationPlatform: MealNotificationPlatform.android,
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
          schedule: (settings, {required isCurrent}) async {
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
