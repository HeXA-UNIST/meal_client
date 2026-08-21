import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @title.
  ///
  /// In ko, this message translates to:
  /// **'밥먹어U'**
  String get title;

  /// No description provided for @close.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get close;

  /// No description provided for @announcement.
  ///
  /// In ko, this message translates to:
  /// **'공지사항'**
  String get announcement;

  /// No description provided for @noAnnouncement.
  ///
  /// In ko, this message translates to:
  /// **'공지사항이 없어요.'**
  String get noAnnouncement;

  /// No description provided for @cannotLoadAnnouncement.
  ///
  /// In ko, this message translates to:
  /// **'공지사항을 불러올 수 없어요.'**
  String get cannotLoadAnnouncement;

  /// No description provided for @operationHours.
  ///
  /// In ko, this message translates to:
  /// **'운영 시간'**
  String get operationHours;

  /// No description provided for @weekday.
  ///
  /// In ko, this message translates to:
  /// **'평일'**
  String get weekday;

  /// No description provided for @weekend.
  ///
  /// In ko, this message translates to:
  /// **'주말'**
  String get weekend;

  /// No description provided for @cannotLoadOperationHours.
  ///
  /// In ko, this message translates to:
  /// **'운영 시간을 불러올 수 없어요.'**
  String get cannotLoadOperationHours;

  /// No description provided for @noOperationHours.
  ///
  /// In ko, this message translates to:
  /// **'등록된 운영 시간이 없어요.'**
  String get noOperationHours;

  /// No description provided for @contactDeveloper.
  ///
  /// In ko, this message translates to:
  /// **'개발자에게 문의하기'**
  String get contactDeveloper;

  /// No description provided for @mon.
  ///
  /// In ko, this message translates to:
  /// **'월'**
  String get mon;

  /// No description provided for @tue.
  ///
  /// In ko, this message translates to:
  /// **'화'**
  String get tue;

  /// No description provided for @wed.
  ///
  /// In ko, this message translates to:
  /// **'수'**
  String get wed;

  /// No description provided for @thu.
  ///
  /// In ko, this message translates to:
  /// **'목'**
  String get thu;

  /// No description provided for @fri.
  ///
  /// In ko, this message translates to:
  /// **'금'**
  String get fri;

  /// No description provided for @sat.
  ///
  /// In ko, this message translates to:
  /// **'토'**
  String get sat;

  /// No description provided for @sun.
  ///
  /// In ko, this message translates to:
  /// **'일'**
  String get sun;

  /// No description provided for @breakfast.
  ///
  /// In ko, this message translates to:
  /// **'아침'**
  String get breakfast;

  /// No description provided for @lunch.
  ///
  /// In ko, this message translates to:
  /// **'점심'**
  String get lunch;

  /// No description provided for @dinner.
  ///
  /// In ko, this message translates to:
  /// **'저녁'**
  String get dinner;

  /// No description provided for @cannotLoadMeal.
  ///
  /// In ko, this message translates to:
  /// **'식단 정보를 불러올 수 없어요.'**
  String get cannotLoadMeal;

  /// No description provided for @noMeal.
  ///
  /// In ko, this message translates to:
  /// **'식단 정보가 없어요.'**
  String get noMeal;

  /// No description provided for @nextWeekPreview.
  ///
  /// In ko, this message translates to:
  /// **'다음 주 식단 미리보기'**
  String get nextWeekPreview;

  /// No description provided for @previewingNextWeek.
  ///
  /// In ko, this message translates to:
  /// **'다음 주 미리보기 중'**
  String get previewingNextWeek;

  /// No description provided for @nextWeekNotReady.
  ///
  /// In ko, this message translates to:
  /// **'다음 주 식단이 아직 준비되지 않았어요.'**
  String get nextWeekNotReady;

  /// No description provided for @language.
  ///
  /// In ko, this message translates to:
  /// **'언어 / Language'**
  String get language;

  /// No description provided for @dormitoryCafeteria.
  ///
  /// In ko, this message translates to:
  /// **'기숙사 식당'**
  String get dormitoryCafeteria;

  /// No description provided for @studentCafeteria.
  ///
  /// In ko, this message translates to:
  /// **'학생 식당'**
  String get studentCafeteria;

  /// No description provided for @facultyCafeteria.
  ///
  /// In ko, this message translates to:
  /// **'교직원 식당'**
  String get facultyCafeteria;

  /// No description provided for @menuKorean.
  ///
  /// In ko, this message translates to:
  /// **'한식'**
  String get menuKorean;

  /// No description provided for @menuHalal.
  ///
  /// In ko, this message translates to:
  /// **'할랄'**
  String get menuHalal;

  /// No description provided for @cafeteriaWithMealType.
  ///
  /// In ko, this message translates to:
  /// **'{cafeteria}({mealType})'**
  String cafeteriaWithMealType(String cafeteria, String mealType);

  /// No description provided for @menuSectionConvenience.
  ///
  /// In ko, this message translates to:
  /// **'간편식'**
  String get menuSectionConvenience;

  /// No description provided for @menuSectionSpecial.
  ///
  /// In ko, this message translates to:
  /// **'특별식'**
  String get menuSectionSpecial;

  /// No description provided for @settings.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settings;

  /// No description provided for @allergyWarning.
  ///
  /// In ko, this message translates to:
  /// **'알레르기 경고'**
  String get allergyWarning;

  /// No description provided for @manageAllergies.
  ///
  /// In ko, this message translates to:
  /// **'알레르기 관리'**
  String get manageAllergies;

  /// No description provided for @noAllergenSelected.
  ///
  /// In ko, this message translates to:
  /// **'선택된 알레르기 없음'**
  String get noAllergenSelected;

  /// No description provided for @allergenSelectedCount.
  ///
  /// In ko, this message translates to:
  /// **'{count}개 선택됨'**
  String allergenSelectedCount(int count);

  /// No description provided for @themeMode.
  ///
  /// In ko, this message translates to:
  /// **'화면 모드'**
  String get themeMode;

  /// No description provided for @themeModeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In ko, this message translates to:
  /// **'라이트'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In ko, this message translates to:
  /// **'다크'**
  String get themeModeDark;

  /// No description provided for @mealNotifications.
  ///
  /// In ko, this message translates to:
  /// **'식단 알림'**
  String get mealNotifications;

  /// No description provided for @notificationSettings.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정'**
  String get notificationSettings;

  /// No description provided for @notificationDescription.
  ///
  /// In ko, this message translates to:
  /// **'선택한 식당과 시간대에 맞춰 푸시 알림을 보내드립니다.'**
  String get notificationDescription;

  /// No description provided for @mealNotificationTitle.
  ///
  /// In ko, this message translates to:
  /// **'{cafeteria} {mealPeriod} 메뉴를 알려드려요.'**
  String mealNotificationTitle(String cafeteria, String mealPeriod);

  /// No description provided for @notificationTodayBreakfast.
  ///
  /// In ko, this message translates to:
  /// **'오늘 아침'**
  String get notificationTodayBreakfast;

  /// No description provided for @notificationTodayLunch.
  ///
  /// In ko, this message translates to:
  /// **'오늘 점심'**
  String get notificationTodayLunch;

  /// No description provided for @notificationTodayDinner.
  ///
  /// In ko, this message translates to:
  /// **'오늘 저녁'**
  String get notificationTodayDinner;

  /// No description provided for @notificationTomorrowBreakfast.
  ///
  /// In ko, this message translates to:
  /// **'내일 아침'**
  String get notificationTomorrowBreakfast;

  /// No description provided for @keywordMealNotificationTitle.
  ///
  /// In ko, this message translates to:
  /// **'{period} \"{keyword}\" 메뉴가 있어요!'**
  String keywordMealNotificationTitle(String period, String keyword);

  /// No description provided for @multipleKeywordMealNotificationTitle.
  ///
  /// In ko, this message translates to:
  /// **'{period} 매칭된 메뉴가 있어요!'**
  String multipleKeywordMealNotificationTitle(String period);

  /// No description provided for @notificationKeywordLabel.
  ///
  /// In ko, this message translates to:
  /// **'키워드'**
  String get notificationKeywordLabel;

  /// No description provided for @notificationKeywordHint.
  ///
  /// In ko, this message translates to:
  /// **'메뉴 키워드를 입력하세요.'**
  String get notificationKeywordHint;

  /// No description provided for @addNotificationKeyword.
  ///
  /// In ko, this message translates to:
  /// **'키워드 추가'**
  String get addNotificationKeyword;

  /// No description provided for @notificationTimesLabel.
  ///
  /// In ko, this message translates to:
  /// **'알림 시간'**
  String get notificationTimesLabel;

  /// No description provided for @notificationTimeSelectionRequired.
  ///
  /// In ko, this message translates to:
  /// **'알림 받을 시간대를 하나 이상 켜주세요.'**
  String get notificationTimeSelectionRequired;

  /// No description provided for @notificationPeriodNight.
  ///
  /// In ko, this message translates to:
  /// **'밤 (내일 아침)'**
  String get notificationPeriodNight;

  /// No description provided for @notificationCafeteriasLabel.
  ///
  /// In ko, this message translates to:
  /// **'알림 대상 식당'**
  String get notificationCafeteriasLabel;

  /// No description provided for @notificationDaysLabel.
  ///
  /// In ko, this message translates to:
  /// **'알림 받을 요일'**
  String get notificationDaysLabel;

  /// No description provided for @about.
  ///
  /// In ko, this message translates to:
  /// **'앱 정보'**
  String get about;

  /// No description provided for @openSourceLicenses.
  ///
  /// In ko, this message translates to:
  /// **'오픈소스 라이선스'**
  String get openSourceLicenses;

  /// No description provided for @notificationPermissionDenied.
  ///
  /// In ko, this message translates to:
  /// **'알림 권한이 차단되었습니다. 설정에서 허용해주세요.'**
  String get notificationPermissionDenied;

  /// No description provided for @notificationPermissionUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'알림이 현재 표시되지 않을 수 있습니다. 시스템 설정에서 권한을 확인해주세요.'**
  String get notificationPermissionUnavailable;

  /// No description provided for @openSystemAppSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정 열기'**
  String get openSystemAppSettings;

  /// No description provided for @androidNotificationTimingNotice.
  ///
  /// In ko, this message translates to:
  /// **'Android에서는 기기 절전 상태에 따라 알림이 선택한 시각보다 늦게 도착할 수 있습니다.'**
  String get androidNotificationTimingNotice;

  /// No description provided for @notificationSyncFailed.
  ///
  /// In ko, this message translates to:
  /// **'알림 설정을 적용하지 못했습니다.'**
  String get notificationSyncFailed;

  /// No description provided for @retry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get retry;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
