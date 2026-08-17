import 'package:meal_client/domain/meal.dart';

/// API 관련 상수
class ApiConstants {
  static const baseUrl = 'https://meal.hexa.pro';
  static const mealEndpoint = '$baseUrl/v2/menu';
  static const noticeEndpoint = '$baseUrl/notice';
  static const infoEndpoint = '$baseUrl/v2/info';

  static String mealEndpointFor(String date) => '$mealEndpoint/$date';
}

/// 로컬 저장소 키
class StorageKeys {
  static const mealCacheFile = 'meal.json';
  static const nextMealCacheFile = 'meal-next.json';
  static const infoCacheFile = 'info.json';
  static const announcementKey = 'announceTime';

  // 설정 (settings_* prefix로 통일)
  static const allergenIds = 'settings_allergen_ids';
  static const notificationEnabled = 'settings_notification_enabled';
  static const notificationKeywords = 'settings_notification_keywords';
  static const notificationCafeterias = 'settings_notification_cafeterias';

  /// 기숙사 식당의 알림 대상 메뉴 종류(한식/할랄) 저장 키.
  /// 키가 없으면 한식·할랄 모두 대상(기본값).
  static const notificationDormMealTypes =
      'settings_notification_dorm_meal_types';

  /// 시간대별 알림 시각 저장 키 prefix.
  /// 실제 키는 `${notificationPeriodTimePrefix}${period.name}` 형태로,
  /// 값은 'HH:MM' 문자열. 키가 없으면 그 시간대는 꺼진 상태.
  static const notificationPeriodTimePrefix =
      'settings_notification_period_time_';

  /// 시간대별 "마지막으로 선택한 알림 시각" 저장 키 prefix.
  /// 해당 시간대를 꺼도 지워지지 않아, 다시 켤 때 이전 시각을 복원하는 데 쓴다.
  /// 실제 키는 `${notificationPeriodRememberedPrefix}${period.name}` 형태.
  static const notificationPeriodRememberedPrefix =
      'settings_notification_period_remembered_';

  /// 알림을 받을 요일 저장 키. 값은 켜진 요일의 [DayOfWeek.name] 리스트.
  /// 키가 없으면 모든 요일 활성(기본값).
  static const notificationDays = 'settings_notification_days';
  static const widgetCafeteria = 'settings_widget_cafeteria';
  static const widgetMealOfDay = 'settings_widget_meal_of_day';
  static const themeMode = 'settings_theme_mode';
}

/// 식사 시간 기준 (KST 기준)
class MealTimeConfig {
  /// 한국 표준시(UTC+9) 보정값.
  static const kstOffset = Duration(hours: 9);

  /// 주어진 시각을 KST로 변환한다.
  static DateTime toKst(DateTime time) => time.toUtc().add(kstOffset);

  /// 주간 메뉴 캐시 판별용 KST 기준 주 ID.
  ///
  /// 1970-01-05는 월요일이므로, KST로 보정한 시각을 이 기준점에서
  /// 7일 단위로 나누면 연도 경계와 ISO week-number 영향을 받지 않는다.
  static int kstWeekId(DateTime time) {
    final kstTime = toKst(time);
    final epoch = DateTime.utc(1970, 1, 5);
    return kstTime.difference(epoch).inDays ~/ 7;
  }

  /// 아침: ~09:20까지
  static const breakfastEndHour = 9;
  static const breakfastEndMinute = 20;

  /// 점심: ~13:30까지
  static const lunchEndHour = 13;
  static const lunchEndMinute = 30;

  /// 그 이후는 저녁

  /// 주어진 KST 시각에 해당하는 식사 시간대를 반환한다.
  /// [kstNow]를 파라미터로 받아 테스트 가능.
  static MealOfDay determineMealOfDay(DateTime kstNow) {
    if (kstNow.hour < breakfastEndHour ||
        (kstNow.hour == breakfastEndHour &&
            kstNow.minute <= breakfastEndMinute)) {
      return MealOfDay.breakfast;
    } else if (kstNow.hour < lunchEndHour ||
        (kstNow.hour == lunchEndHour && kstNow.minute <= lunchEndMinute)) {
      return MealOfDay.lunch;
    } else {
      return MealOfDay.dinner;
    }
  }
}
