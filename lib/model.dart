import 'package:flutter/foundation.dart';

import 'i18n.dart';
import 'meal.dart';

class BapUModel extends ChangeNotifier {
  Language language;
  Brightness brightness;

  int month;
  int day;
  MealOfDay mealOfDay;

  BapUModel({
    required this.language,
    required this.brightness,
    required this.month,
    required this.day,
    required this.mealOfDay,
  });

  void switchToNextMealOfDay() {
    mealOfDay = nextMealOfDay(mealOfDay);
    notifyListeners();
  }
}
