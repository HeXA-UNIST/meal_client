import 'package:meal_client/domain/meal.dart';

class HomePageModel {
  MealOfDay mealOfDay;
  DayOfWeek dayOfWeek;

  HomePageModel({
    required this.mealOfDay,
    required this.dayOfWeek,
  });
}
