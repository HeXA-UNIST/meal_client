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

enum Cafeteria { dormitory, student, employee }

class CafeteriaMeal {
  final List<Meal> dormitory;
  final List<Meal> student;
  final List<Meal> faculty;

  const CafeteriaMeal({
    required this.dormitory,
    required this.student,
    required this.faculty,
  });

  CafeteriaMeal.empty()
    : dormitory = List.empty(growable: true),
      student = List.empty(growable: true),
      faculty = List.empty(growable: true);

  List<Meal> fromCafeteria(Cafeteria r) {
    switch (r) {
      case Cafeteria.dormitory:
        return dormitory;
      case Cafeteria.student:
        return student;
      case Cafeteria.employee:
        return faculty;
    }
  }
}

enum MealOfDay { breakfast, lunch, dinner }

MealOfDay nextMealOfDay(MealOfDay m) {
  switch (m) {
    case MealOfDay.breakfast:
      return MealOfDay.lunch;
    case MealOfDay.lunch:
      return MealOfDay.dinner;
    case MealOfDay.dinner:
      return MealOfDay.breakfast;
  }
}

class DayMeal {
  final CafeteriaMeal breakfast;
  final CafeteriaMeal lunch;
  final CafeteriaMeal dinner;

  const DayMeal({
    required this.breakfast,
    required this.lunch,
    required this.dinner,
  });

  DayMeal.empty()
    : breakfast = CafeteriaMeal.empty(),
      lunch = CafeteriaMeal.empty(),
      dinner = CafeteriaMeal.empty();

  CafeteriaMeal fromMealOfDay(MealOfDay m) {
    switch (m) {
      case MealOfDay.breakfast:
        return breakfast;
      case MealOfDay.lunch:
        return lunch;
      case MealOfDay.dinner:
        return dinner;
    }
  }
}

enum DayOfWeek { mon, tue, wed, thu, fri, sat, sun }

DayOfWeek nextDayOfWeek(DayOfWeek d) {
  switch (d) {
    case DayOfWeek.mon:
      return DayOfWeek.tue;
    case DayOfWeek.tue:
      return DayOfWeek.wed;
    case DayOfWeek.wed:
      return DayOfWeek.thu;
    case DayOfWeek.thu:
      return DayOfWeek.fri;
    case DayOfWeek.fri:
      return DayOfWeek.sat;
    case DayOfWeek.sat:
      return DayOfWeek.sun;
    case DayOfWeek.sun:
      return DayOfWeek.mon;
  }
}

class WeekMeal {
  final DayMeal mon;
  final DayMeal tue;
  final DayMeal wed;
  final DayMeal thu;
  final DayMeal fri;
  final DayMeal sat;
  final DayMeal sun;

  const WeekMeal({
    required this.mon,
    required this.tue,
    required this.wed,
    required this.thu,
    required this.fri,
    required this.sat,
    required this.sun,
  });

  WeekMeal.empty()
    : mon = DayMeal.empty(),
      tue = DayMeal.empty(),
      wed = DayMeal.empty(),
      thu = DayMeal.empty(),
      fri = DayMeal.empty(),
      sat = DayMeal.empty(),
      sun = DayMeal.empty();

  DayMeal fromDayOfWeek(DayOfWeek d) {
    switch (d) {
      case DayOfWeek.mon:
        return mon;
      case DayOfWeek.tue:
        return tue;
      case DayOfWeek.wed:
        return wed;
      case DayOfWeek.thu:
        return thu;
      case DayOfWeek.fri:
        return fri;
      case DayOfWeek.sat:
        return sat;
      case DayOfWeek.sun:
        return sun;
    }
  }
}
