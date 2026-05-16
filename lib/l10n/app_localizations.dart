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

  /// No description provided for @appearance.
  ///
  /// In ko, this message translates to:
  /// **'화면'**
  String get appearance;

  /// No description provided for @themeMode.
  ///
  /// In ko, this message translates to:
  /// **'테마'**
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

  /// No description provided for @notificationSettings.
  ///
  /// In ko, this message translates to:
  /// **'식단 알림'**
  String get notificationSettings;

  /// No description provided for @notificationKeywordLabel.
  ///
  /// In ko, this message translates to:
  /// **'키워드'**
  String get notificationKeywordLabel;

  /// No description provided for @notificationKeywordHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 돈까스'**
  String get notificationKeywordHint;

  /// No description provided for @notificationTimeLabel.
  ///
  /// In ko, this message translates to:
  /// **'알림 시간'**
  String get notificationTimeLabel;

  /// No description provided for @notificationCafeteriasLabel.
  ///
  /// In ko, this message translates to:
  /// **'알림 대상 식당'**
  String get notificationCafeteriasLabel;

  /// No description provided for @widgetSettings.
  ///
  /// In ko, this message translates to:
  /// **'홈 화면 위젯'**
  String get widgetSettings;

  /// No description provided for @widgetCafeteriaLabel.
  ///
  /// In ko, this message translates to:
  /// **'표시할 식당'**
  String get widgetCafeteriaLabel;

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
  /// **'알림 권한이 없습니다. 설정에서 허용해주세요.'**
  String get notificationPermissionDenied;

  /// No description provided for @openSystemAppSettings.
  ///
  /// In ko, this message translates to:
  /// **'설정 열기'**
  String get openSystemAppSettings;
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
