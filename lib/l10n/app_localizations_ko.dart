// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get title => '밥먹어U';

  @override
  String get close => '닫기';

  @override
  String get announcement => '공지사항';

  @override
  String get noAnnouncement => '공지사항이 없어요.';

  @override
  String get cannotLoadAnnouncement => '공지사항을 불러올 수 없어요.';

  @override
  String get operationHours => '운영 시간';

  @override
  String get contactDeveloper => '개발자에게 문의하기';

  @override
  String get mon => '월';

  @override
  String get tue => '화';

  @override
  String get wed => '수';

  @override
  String get thu => '목';

  @override
  String get fri => '금';

  @override
  String get sat => '토';

  @override
  String get sun => '일';

  @override
  String get breakfast => '아침';

  @override
  String get lunch => '점심';

  @override
  String get dinner => '저녁';

  @override
  String get cannotLoadMeal => '식단 정보를 불러올 수 없어요.';

  @override
  String get noMeal => '식단 정보가 없어요.';

  @override
  String get language => '언어 / Language';

  @override
  String get dormitoryCafeteria => '기숙사 식당';

  @override
  String get studentCafeteria => '학생 식당';

  @override
  String get facultyCafeteria => '교직원 식당';

  @override
  String get menuKorean => '한식';

  @override
  String get menuHalal => '할랄';

  @override
  String get settings => '설정';

  @override
  String get allergyWarning => '알레르기 경고';

  @override
  String get manageAllergies => '알레르기 관리';

  @override
  String get noAllergenSelected => '선택된 알레르기 없음';

  @override
  String allergenSelectedCount(int count) {
    return '$count개 선택됨';
  }

  @override
  String get appearance => '화면';

  @override
  String get themeMode => '테마';

  @override
  String get themeModeSystem => '시스템';

  @override
  String get themeModeLight => '라이트';

  @override
  String get themeModeDark => '다크';

  @override
  String get notificationSettings => '식단 알림';

  @override
  String get notificationKeywordLabel => '키워드';

  @override
  String get notificationKeywordHint => '예: 돈까스';

  @override
  String get notificationTimeLabel => '알림 시간';

  @override
  String get notificationPeriodNight => '밤 (내일 아침)';

  @override
  String get notificationCafeteriasLabel => '알림 대상 식당';

  @override
  String get widgetSettings => '홈 화면 위젯';

  @override
  String get widgetCafeteriaLabel => '표시할 식당';

  @override
  String get about => '앱 정보';

  @override
  String get openSourceLicenses => '오픈소스 라이선스';

  @override
  String get notificationPermissionDenied => '알림 권한이 없습니다. 설정에서 허용해주세요.';

  @override
  String get openSystemAppSettings => '설정 열기';
}
