import 'dart:convert';

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

class Meal {
  final List<String> menu;
  final int? kcal;

  const Meal(this.menu, this.kcal);
}

class KoreanMeal extends Meal {
  const KoreanMeal(super.menu, super.kcal);
}

class HalalMeal extends Meal {
  const HalalMeal(super.menu, super.kcal);
}

enum Cafeteria {
  dormitory('기숙사 식당'), // 새 API 전환 시 'DORMITORY'로 변경
  student('학생 식당'),
  faculty('교직원 식당');

  final String apiKey;
  const Cafeteria(this.apiKey);

  static Cafeteria fromApiKey(String key) =>
      values.firstWhere((e) => e.apiKey == key,
          orElse: () => throw FormatException('알 수 없는 restaurantType: $key'));
}

class CafeteriaMeal {
  final List<List<Meal>> _cafeterias;

  CafeteriaMeal._(this._cafeterias)
      : assert(_cafeterias.length == Cafeteria.values.length);

  factory CafeteriaMeal.empty() => CafeteriaMeal._(
      List.generate(Cafeteria.values.length, (_) => <Meal>[]));

  List<Meal> operator [](Cafeteria c) => _cafeterias[c.index];
  List<Meal> fromCafeteria(Cafeteria c) => _cafeterias[c.index];
}

enum MealOfDay {
  breakfast('BREAKFAST'),
  lunch('LUNCH'),
  dinner('DINNER');

  final String apiKey;
  const MealOfDay(this.apiKey);

  MealOfDay get next => values[(index + 1) % values.length];

  static MealOfDay fromApiKey(String key) =>
      values.firstWhere((e) => e.apiKey == key,
          orElse: () => throw FormatException('알 수 없는 mealType: $key'));
}

class DayMeal {
  final List<CafeteriaMeal> _meals;

  DayMeal._(this._meals) : assert(_meals.length == MealOfDay.values.length);

  factory DayMeal.empty() => DayMeal._(
      List.generate(MealOfDay.values.length, (_) => CafeteriaMeal.empty()));

  CafeteriaMeal operator [](MealOfDay m) => _meals[m.index];
  CafeteriaMeal fromMealOfDay(MealOfDay m) => _meals[m.index];
}

enum DayOfWeek {
  mon, tue, wed, thu, fri, sat, sun;

  // apiKey 없음: 새 API에서 date 문자열로 변경 예정이므로 임시 매핑은 api_v2.dart에 유지
  DayOfWeek get next => values[(index + 1) % values.length];
}

class WeekMeal {
  final List<DayMeal> _days;

  WeekMeal._(this._days) : assert(_days.length == DayOfWeek.values.length);

  factory WeekMeal.empty() => WeekMeal._(
      List.generate(DayOfWeek.values.length, (_) => DayMeal.empty()));

  DayMeal operator [](DayOfWeek d) => _days[d.index];
  DayMeal fromDayOfWeek(DayOfWeek d) => _days[d.index];
}
