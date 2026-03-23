// dart:io는 웹에서 사용 불가하므로 제거하고, HttpException 대신 기본 Exception 사용
import 'dart:convert';

import 'package:http/http.dart';

import 'meal.dart';
import 'platform_http_client.dart';

// 요청마다 클라이언트를 새로 만들지 않고 앱 동안 재사용한다.
final Client _httpClient = createPlatformHttpClient();

Future<String> _fetchRawString(String url) async {
  final response = await _httpClient.get(Uri.parse(url))
    .timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) {
    // HttpException은 dart:io 전용이므로 모든 플랫폼에서 사용 가능한 Exception으로 대체
    throw Exception("HTTP ${response.statusCode}: Response Error");
  }

  return response.body;
}

Future<String> fetchRawMeal() async =>
    await _fetchRawString("https://meal.hexa.pro/mainpage/data");

WeekMeal parseRawMeal(String jsonStr) {
  final weekMeal = WeekMeal.empty();
  final list = jsonDecode(jsonStr) as List<dynamic>;
  for (final Map<String, dynamic> meal in list) {
    final DayMeal dayMeal;
    switch (meal["dayType"]) {
      case "MON":
        dayMeal = weekMeal.mon;
      case "TUE":
        dayMeal = weekMeal.tue;
      case "WED":
        dayMeal = weekMeal.wed;
      case "THU":
        dayMeal = weekMeal.thu;
      case "FRI":
        dayMeal = weekMeal.fri;
      case "SAT":
        dayMeal = weekMeal.sat;
      case "SUN":
        dayMeal = weekMeal.sun;
      default:
        throw FormatException();
    }

    final CafeteriaMeal cafeteriaMeal;
    switch (meal["mealType"]) {
      case "BREAKFAST":
        cafeteriaMeal = dayMeal.breakfast;
      case "LUNCH":
        cafeteriaMeal = dayMeal.lunch;
      case "DINNER":
        cafeteriaMeal = dayMeal.dinner;
      default:
        throw FormatException();
    }

    final List<Meal> meals;
    switch (meal["restaurantType"]) {
      case "기숙사 식당":
        meals = cafeteriaMeal.dormitory;
      case "학생 식당":
        meals = cafeteriaMeal.student;
      case "교직원 식당":
        meals = cafeteriaMeal.faculty;
      default:
        throw FormatException();
    }

    final int? kcal;
    {
      final calorie = meal["calorie"];
      if (calorie == 0) {
        kcal = null;
      } else {
        kcal = calorie;
      }
    }

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
    await _fetchRawString("https://meal.hexa.pro/notice");

String parseRawAnnouncement(String rawAnnouncement) {
  final map = jsonDecode(rawAnnouncement) as Map<String, dynamic>;
  return map["content"] as String;
}
