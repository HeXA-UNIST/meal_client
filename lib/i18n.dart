enum Language { eng, kor }

class MultiLanguageString {
  final String eng;
  final String kor;

  const MultiLanguageString({required this.eng, required this.kor});

  String getLocalizedString(Language l) {
    switch (l) {
      case Language.eng:
        return eng;
      case Language.kor:
        return kor;
    }
  }
}
