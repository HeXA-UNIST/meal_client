// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get title => 'BapU';

  @override
  String get close => 'Close';

  @override
  String get announcement => 'Announcement';

  @override
  String get noAnnouncement => 'There is no announcement.';

  @override
  String get cannotLoadAnnouncement => 'Cannot load announcement.';

  @override
  String get operationHours => 'Operation Hours';

  @override
  String get weekday => 'Weekday';

  @override
  String get weekend => 'Weekend';

  @override
  String get cannotLoadOperationHours => 'Cannot load operation hours.';

  @override
  String get noOperationHours => 'No operation hours available.';

  @override
  String get contactDeveloper => 'Contact Developer';

  @override
  String get mon => 'Mon';

  @override
  String get tue => 'Tue';

  @override
  String get wed => 'Wed';

  @override
  String get thu => 'Thu';

  @override
  String get fri => 'Fri';

  @override
  String get sat => 'Sat';

  @override
  String get sun => 'Sun';

  @override
  String get breakfast => 'Breakfast';

  @override
  String get lunch => 'Lunch';

  @override
  String get dinner => 'Dinner';

  @override
  String get cannotLoadMeal => 'Cannot load meal information.';

  @override
  String get noMeal => 'There\'s no meal information.';

  @override
  String get nextWeekPreview => 'Next Week\'s Menu Preview';

  @override
  String get previewingNextWeek => 'Previewing Next Week';

  @override
  String get nextWeekNotReady => 'Next week\'s menu isn\'t ready yet.';

  @override
  String get language => 'Language / 언어';

  @override
  String get dormitoryCafeteria => 'Dormitory';

  @override
  String get studentCafeteria => 'Student';

  @override
  String get facultyCafeteria => 'Faculty';

  @override
  String get menuKorean => 'Korean';

  @override
  String get menuHalal => 'Halal';

  @override
  String cafeteriaWithMealType(String cafeteria, String mealType) {
    return '$cafeteria ($mealType)';
  }

  @override
  String get menuSectionConvenience => 'Convenience meal';

  @override
  String get menuSectionSpecial => 'Special meal';

  @override
  String get settings => 'Settings';

  @override
  String get allergyWarning => 'Allergy Warning';

  @override
  String get manageAllergies => 'Manage Allergies';

  @override
  String get noAllergenSelected => 'None selected';

  @override
  String allergenSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get themeMode => 'Theme';

  @override
  String get themeModeSystem => 'System';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get notificationSettings => 'Meal Notifications';

  @override
  String get notificationKeywordLabel => 'Keyword';

  @override
  String get notificationKeywordHint => 'e.g. Chicken Cutlet';

  @override
  String get notificationTimeLabel => 'Notification Time';

  @override
  String get notificationPeriodNight => 'Night (Tomorrow morning)';

  @override
  String get notificationCafeteriasLabel => 'Target Cafeterias';

  @override
  String get notificationDaysLabel => 'Notification Days';

  @override
  String get widgetSettings => 'Home Screen Widget';

  @override
  String get widgetCafeteriaLabel => 'Display Cafeteria';

  @override
  String get about => 'About';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get notificationPermissionDenied =>
      'Notification permission denied. Please allow it in settings.';

  @override
  String get openSystemAppSettings => 'Open Settings';
}
