import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_alert_period.dart';
import 'package:meal_client/features/settings/allergy_settings.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:meal_client/features/settings/notification_settings.dart';
import 'package:meal_client/features/settings/widget_settings.dart';
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
      expect(s.cafeterias, equals({Cafeteria.dormitory}));
    });

    test('activePeriods — 시각 설정된 시간대만 포함', () {
      final s = NotificationSettings(alertTimes: {
        MealAlertPeriod.morning: const TimeOfDay(hour: 8, minute: 0),
        MealAlertPeriod.dinner: null,
      });
      expect(s.activePeriods, equals([MealAlertPeriod.morning]));
      expect(s.isPeriodEnabled(MealAlertPeriod.morning), isTrue);
      expect(s.isPeriodEnabled(MealAlertPeriod.dinner), isFalse);
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
        alertTimes: {MealAlertPeriod.lunch: const TimeOfDay(hour: 11, minute: 0)},
      );
      final r = s.reset();
      expect(r.enabled, isFalse);
      expect(r.keywords, isEmpty);
      expect(r.alertTimes, isEmpty);
    });

    test('keywords — 불변 List 반환', () {
      final s = NotificationSettings(keywords: ['돈까스']);
      expect(
        () => (s.keywords as dynamic).add('국'),
        throwsUnsupportedError,
      );
    });

    test('alertTimes — 불변 Map 반환', () {
      final s = NotificationSettings(alertTimes: {
        MealAlertPeriod.morning: const TimeOfDay(hour: 8, minute: 0),
      });
      expect(
        () => (s.alertTimes as dynamic)[MealAlertPeriod.lunch] = null,
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
      final slots = MealAlertPeriod.morning.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 7, minute: 30));
      expect(slots.last, const TimeOfDay(hour: 8, minute: 30));
    });

    test('점심 슬롯: 10:30~11:30 15분 간격 5개', () {
      final slots = MealAlertPeriod.lunch.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 10, minute: 30));
      expect(slots.last, const TimeOfDay(hour: 11, minute: 30));
    });

    test('저녁 슬롯: 16:30~17:30 15분 간격 5개', () {
      final slots = MealAlertPeriod.dinner.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 16, minute: 30));
      expect(slots.last, const TimeOfDay(hour: 17, minute: 30));
    });

    test('밤 슬롯: 21:00~22:00 15분 간격 5개', () {
      final slots = MealAlertPeriod.night.allSlots;
      expect(slots.length, 5);
      expect(slots.first, const TimeOfDay(hour: 21, minute: 0));
      expect(slots.last, const TimeOfDay(hour: 22, minute: 0));
    });

    test('night 시간대는 내일 아침 breakfast 검사', () {
      expect(MealAlertPeriod.night.tomorrow, isTrue);
      expect(MealAlertPeriod.night.mealOfDay, MealOfDay.breakfast);
    });

    test('오늘 시간대는 tomorrow=false', () {
      expect(MealAlertPeriod.morning.tomorrow, isFalse);
      expect(MealAlertPeriod.lunch.tomorrow, isFalse);
      expect(MealAlertPeriod.dinner.tomorrow, isFalse);
    });
  });

  group('WidgetSettings', () {
    test('기본값', () {
      const s = WidgetSettings();
      expect(s.cafeteria, Cafeteria.dormitory);
      expect(s.mealOfDay, MealOfDay.lunch);
    });

    test('copyWith', () {
      const s = WidgetSettings();
      final next = s.copyWith(cafeteria: Cafeteria.student);
      expect(next.cafeteria, Cafeteria.student);
      expect(next.mealOfDay, MealOfDay.lunch);
    });
  });

  group('AppSettings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('기본값으로 초기화', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      expect(settings.allergy.enabledIds, isEmpty);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.notification.enabled, isFalse);
      expect(settings.widget.cafeteria, Cafeteria.dormitory);
    });

    test('toggleAllergen — 추가 및 제거', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.toggleAllergen(1);
      expect(settings.allergy.enabledIds, contains(1));
      settings.toggleAllergen(1);
      expect(settings.allergy.enabledIds, isNot(contains(1)));
    });

    test('toggleAllergen — SharedPreferences에 저장 후 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.toggleAllergen(3);
      settings.toggleAllergen(7);
      final settings2 = AppSettings(prefs);
      expect(settings2.allergy.enabledIds, containsAll([3, 7]));
    });

    test('toggleAllergen — notifyListeners 호출', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      var notified = false;
      settings.addListener(() => notified = true);
      settings.toggleAllergen(5);
      expect(notified, isTrue);
    });

    test('setThemeMode — 저장 및 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.setThemeMode(ThemeMode.dark);
      final settings2 = AppSettings(prefs);
      expect(settings2.themeMode, ThemeMode.dark);
    });

    test('setNotificationEnabled — 저장 및 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.setNotificationEnabled(true);
      final settings2 = AppSettings(prefs);
      expect(settings2.notification.enabled, isTrue);
    });

    test('addNotificationKeyword — 추가 및 중복 방지', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.addNotificationKeyword('떡갈비');
      settings.addNotificationKeyword('국');
      settings.addNotificationKeyword('떡갈비'); // 중복
      expect(settings.notification.keywords, equals(['떡갈비', '국']));
    });

    test('addNotificationKeyword — 빈 문자열·공백 무시', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.addNotificationKeyword('');
      settings.addNotificationKeyword('   ');
      expect(settings.notification.keywords, isEmpty);
    });

    test('removeNotificationKeyword — 제거', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.addNotificationKeyword('떡갈비');
      settings.addNotificationKeyword('국');
      settings.removeNotificationKeyword('떡갈비');
      expect(settings.notification.keywords, equals(['국']));
    });

    test('addNotificationKeyword — SharedPreferences 재로드', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.addNotificationKeyword('떡갈비');
      settings.addNotificationKeyword('국');
      final settings2 = AppSettings(prefs);
      expect(settings2.notification.keywords, equals(['떡갈비', '국']));
    });

    test('구버전 단일 키워드 마이그레이션', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_keyword': '돈까스',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
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
      final settings = AppSettings(prefs);
      settings.setPeriodAlertTime(
        MealAlertPeriod.lunch,
        const TimeOfDay(hour: 11, minute: 0),
      );
      expect(
        settings.notification.alertTimeOf(MealAlertPeriod.lunch),
        const TimeOfDay(hour: 11, minute: 0),
      );
      final settings2 = AppSettings(prefs);
      expect(
        settings2.notification.alertTimeOf(MealAlertPeriod.lunch),
        const TimeOfDay(hour: 11, minute: 0),
      );
    });

    test('setPeriodAlertTime(null) — 시각 제거', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.setPeriodAlertTime(
        MealAlertPeriod.lunch,
        const TimeOfDay(hour: 11, minute: 0),
      );
      settings.setPeriodAlertTime(MealAlertPeriod.lunch, null);
      expect(settings.notification.alertTimeOf(MealAlertPeriod.lunch), isNull);
      expect(settings.notification.activePeriods, isEmpty);
    });

    test('로드: 유효하지 않은 슬롯은 무시', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_period_time_lunch': '11:07', // 15분 슬롯 아님
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      expect(settings.notification.activePeriods, isEmpty);
    });

    test('구버전 단일 알림 시각(08:00) 마이그레이션 → 아침', () async {
      SharedPreferences.setMockInitialValues({
        'settings_notification_time': '8:0',
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      expect(
        settings.notification.alertTimeOf(MealAlertPeriod.morning),
        const TimeOfDay(hour: 8, minute: 0),
      );
      // 구 키는 삭제
      expect(prefs.getString('settings_notification_time'), isNull);
    });

    test('resetAll — 모든 값이 기본값으로', () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      settings.toggleAllergen(1);
      settings.setThemeMode(ThemeMode.dark);
      settings.setNotificationEnabled(true);
      settings.resetAll();
      expect(settings.allergy.enabledIds, isEmpty);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.notification.enabled, isFalse);
    });
  });
}
