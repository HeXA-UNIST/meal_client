import 'meal.dart';

class BapUModel {
  // 추후 Settings 기능 추가 시 사용자 ThemeMode 설정을 여기서 관리할 수 있음
}

class HomePageModel {
  MealOfDay mealOfDay;
  DayOfWeek dayOfWeek;

  HomePageModel({
    required this.mealOfDay,
    required this.dayOfWeek,
  });
}
