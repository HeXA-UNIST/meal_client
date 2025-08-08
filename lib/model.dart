import 'package:flutter/foundation.dart';

import 'i18n.dart';
import 'meal.dart';

class BapUModel extends ChangeNotifier {
  Language _language;
  Brightness _brightness;
  int _month;
  int _day;
  MealOfDay _mealOfDay;

  BapUModel({
    required Language language,
    required Brightness brightness,
    required int month,
    required int day,
    required MealOfDay mealOfDay,
  }) : _language = language,
       _brightness = brightness,
       _month = month,
       _day = day,
       _mealOfDay = mealOfDay;

  Language get language => _language;

  Brightness get brightness => _brightness;

  int get month => _month;

  int get day => _day;

  MealOfDay get mealOfDay => _mealOfDay;

  void changeLanguage(Language language) {
    _language = language;

    notifyListeners();
  }

  void toggleBrightness() {
    if (_brightness == Brightness.light) {
      _brightness = Brightness.dark;
    } else {
      _brightness = Brightness.light;
    }

    notifyListeners();
  }

  void changeDate(int month, int day) {
    _month = month;
    _day = day;

    notifyListeners();
  }

  void switchToNextMealOfDay() {
    _mealOfDay = nextMealOfDay(_mealOfDay);

    notifyListeners();
  }
}
