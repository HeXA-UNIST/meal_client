import 'package:flutter/foundation.dart';

import 'meal.dart';

class BapUModel extends ChangeNotifier {
  Brightness _themeBrightness;

  BapUModel({required Brightness themeBrightness})
    : _themeBrightness = themeBrightness;

  Brightness get themeBrightness => _themeBrightness;

  void setThemeBrightness(Brightness themeBrightness) {
    if (_themeBrightness == themeBrightness) return;

    _themeBrightness = themeBrightness;
    notifyListeners();
  }
}

class HomePageModel {
  MealOfDay mealOfDay;
  DayOfWeek dayOfWeek;

  HomePageModel({
    required this.mealOfDay,
    required this.dayOfWeek,
  });
}
