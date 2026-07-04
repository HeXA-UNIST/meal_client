import 'package:meal_client/domain/meal.dart';

/// API 관련 상수
class ApiConstants {
  static const baseUrl = 'https://meal.hexa.pro';
  static const mealEndpoint = '$baseUrl/v2/menu';
  static const noticeEndpoint = '$baseUrl/notice';
  static const infoEndpoint = '$baseUrl/v2/info';
}

/// 로컬 저장소 키
class StorageKeys {
  static const mealCacheFile = 'meal.json';
  static const announcementKey = 'announceTime';

  // 설정 (settings_* prefix로 통일)
  static const allergenIds             = 'settings_allergen_ids';
  static const notificationEnabled     = 'settings_notification_enabled';
  static const notificationKeyword     = 'settings_notification_keyword';
  static const notificationTime        = 'settings_notification_time';
  static const notificationCafeterias  = 'settings_notification_cafeterias';
  static const widgetCafeteria         = 'settings_widget_cafeteria';
  static const widgetMealOfDay         = 'settings_widget_meal_of_day';
  static const themeMode               = 'settings_theme_mode';
}

/// 식사 시간 기준 (KST 기준)
class MealTimeConfig {
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
