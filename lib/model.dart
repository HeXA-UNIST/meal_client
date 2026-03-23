import 'package:flutter/foundation.dart';

import 'meal.dart';
import 'i18n.dart';

class BapUModel extends ChangeNotifier {
  Language _language;
  Brightness _themeBrightness;

  BapUModel({required Language language, required Brightness themeBrightness})
    : _language = language,
      _themeBrightness = themeBrightness;

  Language get language => _language;

  Brightness get themeBrightness => _themeBrightness;

  void changeLanguage(Language language) {
    if (_language == language) return;

    _language = language;

    notifyListeners();
  }

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
