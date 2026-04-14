import 'package:flutter/material.dart';

import 'meal.dart';

/// 앱 주 색상
const mainColor = Color(0xFF00CD80);

/// API 관련 상수
class ApiConstants {
  static const baseUrl = 'https://meal.hexa.pro';
  static const mealEndpoint = '$baseUrl/mainpage/data';
  static const noticeEndpoint = '$baseUrl/notice';
}

/// 로컬 저장소 키
class StorageKeys {
  static const mealCacheFile = 'meal.json';
  static const announcementKey = 'announceTime';
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
