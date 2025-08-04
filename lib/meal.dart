class Meal {
  final List<String> menu;
  final int? calorie;

  Meal(this.menu, this.calorie);
}

enum Restaurant { dormitory, student, employee }

class RestaurantMeal {
  final List<Meal> dormitory;
  final List<Meal> student;
  final List<Meal> employee;

  RestaurantMeal({
    this.dormitory = const [],
    this.student = const [],
    this.employee = const [],
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

  DayMeal(this.breakfast, this.lunch, this.dinner);

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

  WeekMeal(
    this.mon,
    this.tue,
    this.wed,
    this.thu,
    this.fri,
    this.sat,
    this.sun,
  );

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
