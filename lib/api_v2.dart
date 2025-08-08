import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'meal.dart';

const _url = "https://meal.hexa.pro/mainpage/data";

Future<String> fetchRawMeal() async {
  final response = await http.get(Uri.parse(_url));
  if (response.statusCode != 200) {
    throw HttpException("Not 200");
  }

  return response.body;
}

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

    final int calorie = meal["calorie"];
    meals.add(
      Meal(
        (meal["menus"] as List<dynamic>)
            .map((e) => e as String)
            .toList(growable: false),
        calorie == 0 ? null : calorie,
      ),
    );
  }

  return weekMeal;
}
