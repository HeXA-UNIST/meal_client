import 'dart:ui';

/// Manual date formatting function for localized month-day display.
///
/// This function intentionally does NOT use `intl`'s `DateFormat` —
/// it preserves the exact formatting that was used in the original
/// `getLocalizedDate` from `string.dart`.
///
/// For Korean: "4월 4일"
/// For English: "Apr. 4"
String getLocalizedDate(int month, int day, Locale locale) {
  final isKorean = locale.languageCode == 'ko';

  const engMonths = [
    'Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'Jun.',
    'Jul.', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.',
  ];
  const korMonths = [
    '1월', '2월', '3월', '4월', '5월', '6월',
    '7월', '8월', '9월', '10월', '11월', '12월',
  ];

  if (month < 1 || month > 12) {
    throw FormatException('Invalid month: $month');
  }

  final monthStr = isKorean ? korMonths[month - 1] : engMonths[month - 1];

  if (isKorean) {
    return '$monthStr $day일';
  } else {
    return '$monthStr $day';
  }
}
