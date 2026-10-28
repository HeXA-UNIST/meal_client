import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/meal/meal_cache.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';
import 'package:meal_client/features/notification/notification_scheduler.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/settings/allergy/allergy_settings.dart';
import 'package:meal_client/features/settings/bapu_settings.dart';
import 'package:meal_client/features/settings/locale_settings.dart';
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

  test('알림은 저장한 앱 언어를 읽는다', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.locale: 'ko'});
    expect((await notificationLocalizations()).localeName, 'ko');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.locale, 'en');
    expect((await notificationLocalizations()).localeName, 'en');
  });

  test('최초 지원 언어를 저장하고 이후 시스템 언어 변경에도 유지한다', () async {
    for (final locales in <List<Locale>>[
      [const Locale('ko', 'KR')],
      [const Locale('ja'), const Locale('ko')],
      [const Locale('en')],
      [],
    ]) {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await initializeAppLocale(prefs, platformLocales: locales);
      final expected = resolveInitialAppLocale(locales).languageCode;
      expect(loadAppLocale(prefs).languageCode, expected);
      await initializeAppLocale(
        prefs,
        platformLocales: [Locale(expected == 'ko' ? 'en' : 'ko')],
      );
      expect(loadAppLocale(prefs).languageCode, expected);
    }
  });

  group('AppSettings', () {
    late List<BapuSettings> settingsToDispose;

    BapuSettings createSettings(SharedPreferences prefs) {
      final settings = BapuSettings(
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

    test('앱 언어를 저장하고 재시작 후 복원한다', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = createSettings(prefs);
      await settings.setLocale(const Locale('ko'));
      expect(settings.locale, const Locale('ko'));
      expect(createSettings(prefs).locale, const Locale('ko'));
      await settings.setLocale(const Locale('en'));
      expect(createSettings(prefs).locale, const Locale('en'));
    });

    test('iOS는 알림 표시 권한을 재확인하고 거부 상태는 시스템 설정에서 복구한다', () async {
      final prefs = await SharedPreferences.getInstance();
      var authorization = MealNotificationAuthorizationStatus.notAuthorized;
      var settingsOpened = 0;
      var schedules = 0;
      final settings = BapuSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.ios,
        resumeListenerRegistrar: (_) => () {},
        notificationPermissionRequester: () async => true,
        exactAlarmPermissionRequester: () async =>
            throw StateError('iOS에서는 정확한 알람 권한을 요청하면 안 된다'),
        notificationAuthorizationStatusReader: () async => authorization,
        notificationSettingsOpener: () async {
          settingsOpened++;
          authorization = MealNotificationAuthorizationStatus.enabled;
        },
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (_, {required isCurrent}) async {
            schedules++;
          },
          cancel: () async {},
        ),
      );
      addTearDown(settings.dispose);
      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.permissionDenied,
      );
      expect(settings.notification.enabled, isFalse);
      await settings.restoreNotificationPermission();
      expect(settingsOpened, 1);
      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.enabled,
      );
      expect(settings.notification.enabled, isTrue);
      expect(schedules, 1);
    });

    test('Android 정확한 알람 권한 거부는 설정을 저장하지 않고 허용 후에만 알림을 켠다', () async {
      final prefs = await SharedPreferences.getInstance();
      var authorization =
          MealNotificationAuthorizationStatus.exactAlarmNotAuthorized;
      var allowExact = false;
      var exactRequests = 0;
      var schedules = 0;
      final settings = BapuSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.android,
        resumeListenerRegistrar: (_) => () {},
        notificationPermissionRequester: () async => true,
        exactAlarmPermissionRequester: () async {
          exactRequests++;
          if (allowExact) {
            authorization = MealNotificationAuthorizationStatus.enabled;
          }
          return allowExact;
        },
        notificationAuthorizationStatusReader: () async => authorization,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          debounce: Duration.zero,
          schedule: (_, {required isCurrent}) async {
            schedules++;
          },
          cancel: () async {},
        ),
      );
      addTearDown(settings.dispose);
      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.exactAlarmPermissionDenied,
      );
      expect(settings.notification.enabled, isFalse);
      expect(prefs.getBool(StorageKeys.notificationEnabled) ?? false, isFalse);
      expect(schedules, 0);
      allowExact = true;
      expect(
        await settings.setNotificationEnabled(true),
        NotificationEnableResult.enabled,
      );
      expect(settings.notification.enabled, isTrue);
      expect(prefs.getBool(StorageKeys.notificationEnabled), isTrue);
      expect(exactRequests, 2);
      expect(schedules, 1);
      authorization =
          MealNotificationAuthorizationStatus.exactAlarmNotAuthorized;
      await settings.refreshNotificationAuthorizationStatus();
      expect(settings.notificationAuthorizationStatus, authorization);
      expect(settings.notification.enabled, isTrue);
    });

    for (final displayPermissionGranted in [true, false]) {
      test(
        'Android 설정 복귀에서 표시 권한 ${displayPermissionGranted ? '허용 시 남은 정확한 알람 권한을 요청한다' : '거부 시 복구를 종료한다'}',
        () async {
          SharedPreferences.setMockInitialValues({
            StorageKeys.notificationEnabled: true,
          });
          final prefs = await SharedPreferences.getInstance();
          var authorization = MealNotificationAuthorizationStatus.notAuthorized;
          var settingsOpened = 0;
          var exactRequests = 0;
          var completedResumes = 0;
          VoidCallback? onResume;
          final settings = BapuSettings(
            prefs,
            notificationPlatform: MealNotificationPlatform.android,
            resumeListenerRegistrar: (listener) {
              onResume = listener;
              return () {};
            },
            notificationPermissionRequester: () async =>
                authorization !=
                MealNotificationAuthorizationStatus.notAuthorized,
            exactAlarmPermissionRequester: () async {
              exactRequests++;
              authorization = MealNotificationAuthorizationStatus.enabled;
              return true;
            },
            notificationAuthorizationStatusReader: () async => authorization,
            notificationSettingsOpener: () async => settingsOpened++,
            notificationScheduleCoordinator: NotificationScheduleCoordinator(
              debounce: Duration.zero,
              schedule: (_, {required isCurrent}) async {},
              cancel: () async {},
            ),
            mealCacheRevisionSnapshotReader: () async =>
                (current: null, next: null),
            foregroundMealRefresher: (_, _) async => completedResumes++,
          );
          settingsToDispose.add(settings);

          expect(
            await settings.restoreNotificationPermission(),
            NotificationEnableResult.permissionDenied,
          );
          expect(settingsOpened, 1);
          if (displayPermissionGranted) {
            authorization =
                MealNotificationAuthorizationStatus.exactAlarmNotAuthorized;
          }
          onResume!();
          await _waitUntil(() => completedResumes == 1);
          expect(exactRequests, displayPermissionGranted ? 1 : 0);
          expect(
            settings.notificationAuthorizationStatus,
            displayPermissionGranted
                ? MealNotificationAuthorizationStatus.enabled
                : MealNotificationAuthorizationStatus.notAuthorized,
          );
          expect(settings.notification.enabled, isTrue);
          expect(prefs.getBool(StorageKeys.notificationEnabled), isTrue);

          // 복구 복귀를 한 번 처리한 뒤의 일반 resume에서는 권한을 다시 요청하지 않는다.
          authorization =
              MealNotificationAuthorizationStatus.exactAlarmNotAuthorized;
          onResume!();
          await _waitUntil(() => completedResumes == 2);
          expect(exactRequests, displayPermissionGranted ? 1 : 0);
          expect(settingsOpened, 1);
        },
      );
    }

    test('알림 권한 거부와 시스템 설정에서의 복구를 관찰한다', () async {
      final prefs = await SharedPreferences.getInstance();
      var requestCount = 0;
      var authorization = MealNotificationAuthorizationStatus.notAuthorized;
      VoidCallback? onResume;
      final settings = BapuSettings(
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
      final settings = BapuSettings(
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

    test('알림 저장 실패는 앱 설정만 되돌리고 확인된 OS 권한은 유지한다', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = BapuSettings(
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
      expect(
        settings.notificationAuthorizationStatus,
        MealNotificationAuthorizationStatus.enabled,
      );
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
      final settings = BapuSettings(
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
        notificationAuthorizationStatusReader: () async =>
            MealNotificationAuthorizationStatus.enabled,
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
      final settings = BapuSettings(
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
      final settings = BapuSettings(
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

    test('빠른 설정 변경은 UI에 바로 반영되고 최신 예약 하나로 합쳐진다', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.notificationEnabled: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final scheduledDays = <Set<DayOfWeek>>[];
      final scheduled = Completer<void>();
      final settings = BapuSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.android,
        resumeListenerRegistrar: (_) => () {},
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (settings, {required isCurrent}) async {
            if (isCurrent()) {
              scheduledDays.add({...settings.days});
              if (!scheduled.isCompleted) scheduled.complete();
            }
          },
          cancel: () async {},
        ),
      );
      settingsToDispose.add(settings);

      settings.setNotificationDays({DayOfWeek.mon});
      await _waitUntil(
        () => setEquals(settings.notification.days, {DayOfWeek.mon}),
      );
      settings.setNotificationDays({DayOfWeek.fri});
      await _waitUntil(
        () => setEquals(settings.notification.days, {DayOfWeek.fri}),
      );

      await scheduled.future.timeout(const Duration(seconds: 1));
      expect(scheduledDays, [
        {DayOfWeek.fri},
      ]);
      expect(prefs.getStringList(StorageKeys.notificationDays), ['fri']);
      expect(prefs.getInt(StorageKeys.notificationMutationGeneration), 2);
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
      final settings = BapuSettings(
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

    test('304 재검증 뒤 resume은 1시간 동안 다시 요청하지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.notificationEnabled: true,
      });
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime.utc(2026, 8, 20, 3);
      final raw = _rawWeek('2026-08-17')
          .replaceFirst('{', '{"etag":"menu-v1",');
      var updatedAt = now.subtract(const Duration(hours: 2));
      final cache = MealCache(
        readFile: (_) async => raw,
        writeFile: (_, _) async => fail('동일 본문을 다시 쓰면 안 된다'),
        readLastModified: (_) async => updatedAt,
        setLastModified: (_, at) async => updatedAt = at,
      );
      var fetches = 0;
      final service = MealRefreshService(
        cache: cache,
        clock: () => now,
        fetchConditional: (_, {ifNoneMatch}) async {
          fetches++;
          expect(ifNoneMatch, 'menu-v1');
          return (statusCode: 304, body: null);
        },
      );
      VoidCallback? onResume;
      var snapshotReads = 0;
      final settings = BapuSettings(
        prefs,
        notificationPlatform: MealNotificationPlatform.android,
        resumeListenerRegistrar: (listener) {
          onResume = listener;
          return () {};
        },
        clock: () => now,
        mealCacheRevisionSnapshotReader: () async {
          snapshotReads++;
          return (current: await cache.readRevision(), next: null);
        },
        foregroundMealRefresher: (_, _) async {
          await service.refreshMealResponse(prefetchNextWeek: false);
        },
        notificationAuthorizationStatusReader: () async =>
            MealNotificationAuthorizationStatus.enabled,
        notificationScheduleCoordinator: NotificationScheduleCoordinator(
          schedule: (_, {required isCurrent}) async {},
          cancel: () async {},
        ),
      );
      settingsToDispose.add(settings);

      onResume!();
      await _waitUntil(() => snapshotReads >= 3);
      expect(fetches, 1);
      expect(updatedAt, now);

      now = now.add(const Duration(minutes: 5));
      onResume!();
      await _waitUntil(() => snapshotReads >= 5);
      expect(fetches, 1);

      // 같은 서비스는 Workmanager에서도 사용한다. 백그라운드 재검증도
      // 다음 resume의 제한 시각을 갱신해야 한다.
      now = now.add(const Duration(hours: 2));
      await service.refreshMealResponse(prefetchNextWeek: false);
      onResume!();
      await _waitUntil(() => snapshotReads >= 7);
      expect(fetches, 2);

      now = now.add(const Duration(hours: 1, seconds: 1));
      onResume!();
      await _waitUntil(() => snapshotReads >= 10);
      expect(fetches, 3);
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
      final settings = BapuSettings(
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
