class Meal {
  final List<String> menu;
  final int? kcal;

  Meal(this.menu, this.kcal);
}

enum Restaurant { dormitory, student, employee }

class RestaurantMeal {
  final List<Meal> dormitory;
  final List<Meal> student;
  final List<Meal> employee;

  RestaurantMeal({
    required this.dormitory,
    required this.student,
    required this.employee,
  });

  List<Meal> fromRestaurant(Restaurant r) {
    switch (r) {
      case Restaurant.dormitory:
        return dormitory;
      case Restaurant.student:
        return student;
      case Restaurant.employee:
        return employee;
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
  final RestaurantMeal breakfast;
  final RestaurantMeal lunch;
  final RestaurantMeal dinner;

  DayMeal({required this.breakfast, required this.lunch, required this.dinner});

  RestaurantMeal fromMealOfDay(MealOfDay m) {
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

class WeekMeal {
  final DayMeal mon;
  final DayMeal tue;
  final DayMeal wed;
  final DayMeal thu;
  final DayMeal fri;
  final DayMeal sat;
  final DayMeal sun;

  WeekMeal({
    required this.mon,
    required this.tue,
    required this.wed,
    required this.thu,
    required this.fri,
    required this.sat,
    required this.sun,
  });

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
