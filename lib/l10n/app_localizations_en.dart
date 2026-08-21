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
  String get noMeal => 'There is no meal information.';

  @override
  String get nextWeekPreview => 'Next Week\'s Menu Preview';

  @override
  String get previewingNextWeek => 'Previewing Next Week';

  @override
  String get nextWeekNotReady => 'Next week\'s menu is not ready yet.';

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
  String get themeMode => 'Theme Mode';

  @override
  String get themeModeSystem => 'System';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get mealNotifications => 'Meal Notifications';

  @override
  String get notificationSettings => 'Notification Settings';

  @override
  String get notificationDescription =>
      'Get meal notifications for your selected cafeterias and times.';

  @override
  String mealNotificationTitle(String cafeteria, String mealPeriod) {
    return '$cafeteria $mealPeriod Menu';
  }

  @override
  String get notificationTodayBreakfast => 'Today\'s breakfast';

  @override
  String get notificationTodayLunch => 'Today\'s lunch';

  @override
  String get notificationTodayDinner => 'Today\'s dinner';

  @override
  String get notificationTomorrowBreakfast => 'Tomorrow\'s breakfast';

  @override
  String keywordMealNotificationTitle(String period, String keyword) {
    return '$period: \"$keyword\" is on the menu!';
  }

  @override
  String multipleKeywordMealNotificationTitle(String period) {
    return '$period: Matching menu items found!';
  }

  @override
  String get notificationKeywordLabel => 'Keyword';

  @override
  String get notificationKeywordHint => 'Enter a menu keyword.';

  @override
  String get addNotificationKeyword => 'Add keyword';

  @override
  String get notificationTimesLabel => 'Notification Times';

  @override
  String get notificationTimeSelectionRequired =>
      'Turn on at least one notification time.';

  @override
  String get notificationPeriodNight => 'Night (for Tomorrow Morning)';

  @override
  String get notificationCafeteriasLabel => 'Target Cafeterias';

  @override
  String get notificationDaysLabel => 'Notification Days';

  @override
  String get about => 'About';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get notificationPermissionDenied =>
      'Notification permission denied. Please allow it in settings.';

  @override
  String get notificationPermissionUnavailable =>
      'Notifications may not appear. Check the permission in system settings.';

  @override
  String get openSystemAppSettings => 'Open Settings';

  @override
  String get androidNotificationTimingNotice =>
      'On Android, device power restrictions may delay notifications beyond the selected time.';

  @override
  String get notificationSyncFailed =>
      'Notification settings could not be applied.';

  @override
  String get retry => 'Retry';
}
