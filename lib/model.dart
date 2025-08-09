import 'package:flutter/foundation.dart';

import 'i18n.dart';

class BapUModel extends ChangeNotifier {
  Language _language;
  Brightness _brightness;

  BapUModel({required Language language, required Brightness brightness})
    : _language = language,
      _brightness = brightness;

  Language get language => _language;

  Brightness get brightness => _brightness;

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
}
