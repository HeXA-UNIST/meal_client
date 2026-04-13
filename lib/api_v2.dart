// dart:io는 웹에서 사용 불가하므로 제거하고, HttpException 대신 기본 Exception 사용
import 'dart:convert';

import 'package:http/http.dart';

import 'constants.dart';
import 'meal.dart';
import 'platform_http_client.dart';

// 요청마다 클라이언트를 새로 만들지 않고 앱 동안 재사용한다.
final Client _httpClient = createPlatformHttpClient();

Future<String> _fetchRawString(String url) async {
  final response = await _httpClient
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    // HttpException은 dart:io 전용이므로 모든 플랫폼에서 사용 가능한 Exception으로 대체
    throw Exception("HTTP ${response.statusCode}: Response Error");
  }

  return response.body;
}

Future<String> fetchRawMeal() async =>
    await _fetchRawString(ApiConstants.mealEndpoint);

// api_v2.dart 내부 — 새 API 전환 시 date 파싱으로 교체
const _dayTypeMap = {
  'MON': DayOfWeek.mon,
  'TUE': DayOfWeek.tue,
  'WED': DayOfWeek.wed,
  'THU': DayOfWeek.thu,
  'FRI': DayOfWeek.fri,
  'SAT': DayOfWeek.sat,
  'SUN': DayOfWeek.sun,
};

WeekMeal parseRawMeal(String jsonStr) {
  final weekMeal = WeekMeal.empty();
  final list = jsonDecode(jsonStr) as List<dynamic>;
  for (final Map<String, dynamic> meal in list) {
    final dayOfWeek = _dayTypeMap[meal["dayType"]];
    if (dayOfWeek == null) {
      throw FormatException('알 수 없는 dayType: ${meal["dayType"]}');
    }
    final mealOfDay = MealOfDay.fromApiKey(meal["mealType"] as String? ?? '');
    final cafeteria = Cafeteria.fromApiKey(meal["restaurantType"] as String? ?? '');

    final meals = weekMeal[dayOfWeek][mealOfDay][cafeteria];

    final calorie = meal["calorie"];
    final kcal = calorie == 0 ? null : (calorie is num ? calorie.toInt() : null);

    final menu = (meal["menus"] as List<dynamic>)
        .map((e) => e as String)
        .toList(growable: false);

    if (meal.containsKey("dormitoryType")) {
      switch (meal["dormitoryType"]) {
        case "KOREAN":
          meals.add(KoreanMeal(menu, kcal));
        case "HALAL":
          meals.add(HalalMeal(menu, kcal));
        default:
          meals.add(Meal(menu, kcal));
      }
    } else {
      meals.add(Meal(menu, kcal));
    }
  }

  return weekMeal;
}

Future<String> fetchRawAnnouncement() async =>
    await _fetchRawString(ApiConstants.noticeEndpoint);

String parseRawAnnouncement(String rawAnnouncement) {
  final map = jsonDecode(rawAnnouncement) as Map<String, dynamic>;
  return map["content"] as String;
}
