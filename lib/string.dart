import 'i18n.dart';

const title = MultiLanguageString(eng: "BapU", kor: "밥먹어U");

const notification = MultiLanguageString(eng: "Announcement", kor: "공지사항");
const operationinfo = MultiLanguageString(eng: "Operation Info", kor: "운영 정보");
const contactdeveloper = MultiLanguageString(
  eng: "Contact Developer",
  kor: "개발자에게 문의하기",
);

const mon = MultiLanguageString(eng: "Mon", kor: "월");
const tue = MultiLanguageString(eng: "Tue", kor: "화");
const wed = MultiLanguageString(eng: "Wed", kor: "수");
const thu = MultiLanguageString(eng: "Thu", kor: "목");
const fri = MultiLanguageString(eng: "Fri", kor: "금");
const sat = MultiLanguageString(eng: "Sat", kor: "토");
const sun = MultiLanguageString(eng: "Sun", kor: "일");

const breakfast = MultiLanguageString(eng: "Breakfast", kor: "아침");
const lunch = MultiLanguageString(eng: "Lunch", kor: "점심");
const dinner = MultiLanguageString(eng: "Dinner", kor: "저녁");

const cannotLoadMeal = MultiLanguageString(
  eng: "Cannot load meal information.",
  kor: "식단 정보를 불러올 수 없어요.",
);

const _jan = MultiLanguageString(eng: "Jan.", kor: "1월");
const _feb = MultiLanguageString(eng: "Feb.", kor: "2월");
const _mar = MultiLanguageString(eng: "Mar.", kor: "3월");
const _apr = MultiLanguageString(eng: "Apr.", kor: "4월");
const _may = MultiLanguageString(eng: "May", kor: "5월");
const _jun = MultiLanguageString(eng: "Jun.", kor: "6월");
const _jul = MultiLanguageString(eng: "Jul.", kor: "7월");
const _aug = MultiLanguageString(eng: "Aug.", kor: "8월");
const _sep = MultiLanguageString(eng: "Sep.", kor: "9월");
const _oct = MultiLanguageString(eng: "Oct.", kor: "10월");
const _nov = MultiLanguageString(eng: "Nov.", kor: "11월");
const _dec = MultiLanguageString(eng: "Dec.", kor: "12월");

String getLocalizedDate(int month, int day, Language lang) {
  String date = "";
  switch (month) {
    case 1:
      date += _jan.getLocalizedString(lang);
    case 2:
      date += _feb.getLocalizedString(lang);
    case 3:
      date += _mar.getLocalizedString(lang);
    case 4:
      date += _apr.getLocalizedString(lang);
    case 5:
      date += _may.getLocalizedString(lang);
    case 6:
      date += _jun.getLocalizedString(lang);
    case 7:
      date += _jul.getLocalizedString(lang);
    case 8:
      date += _aug.getLocalizedString(lang);
    case 9:
      date += _sep.getLocalizedString(lang);
    case 10:
      date += _oct.getLocalizedString(lang);
    case 11:
      date += _nov.getLocalizedString(lang);
    case 12:
      date += _dec.getLocalizedString(lang);
    default:
      throw FormatException();
  }

  date += " $day";
  if (lang == Language.kor) {
    date += "일";
  }

  return date;
}
