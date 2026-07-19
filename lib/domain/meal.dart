import 'dart:convert';

WeekMeal parseRawMeal(String jsonStr) {
  final root = _requiredMap(jsonDecode(jsonStr), 'root');
  final weekMeal = WeekMeal.empty();
  final data = _requiredList(root['data'], 'data');

  for (final cafeteriaValue in data) {
    final cafeteriaJson = _requiredMap(cafeteriaValue, 'data[]');
    final cafeteria = Cafeteria.fromApiKey(
      _requiredString(cafeteriaJson['cafeteria'], 'data[].cafeteria'),
    );
    final meals = _requiredList(cafeteriaJson['meals'], 'data[].meals');

    for (final mealValue in meals) {
      final mealJson = _requiredMap(mealValue, 'data[].meals[]');
      final dayOfWeek = DayOfWeek.fromApiKey(
        _requiredString(mealJson['dayOfWeek'], 'data[].meals[].dayOfWeek'),
      );
      final mealOfDay = MealOfDay.fromApiKey(
        _requiredString(mealJson['timeType'], 'data[].meals[].timeType'),
      );
      final cafeteriaMeals = weekMeal[dayOfWeek][mealOfDay][cafeteria];
      final menuGroups = _requiredList(
        mealJson['menusByType'],
        'data[].meals[].menusByType',
      );

      for (final groupValue in menuGroups) {
        final groupJson = _requiredMap(
          groupValue,
          'data[].meals[].menusByType[]',
        );
        final menuType = _requiredString(
          groupJson['menuType'],
          'data[].meals[].menusByType[].menuType',
        );
        final sections = _requiredList(
          groupJson['sections'],
          'data[].meals[].menusByType[].sections',
        );
        final mealSections = <MealSection>[];

        for (final sectionValue in sections) {
          final sectionJson = _requiredMap(
            sectionValue,
            'data[].meals[].menusByType[].sections[]',
          );
          final sectionType = MealSectionType.fromApiKey(
            _requiredString(
              sectionJson['sectionType'],
              'data[].meals[].menusByType[].sections[].sectionType',
            ),
          );
          if (sectionType == null || sectionType == MealSectionType.salad) {
            continue;
          }

          final calorie = sectionJson['calorie'];
          final menus = _requiredList(
            sectionJson['menus'],
            'data[].meals[].menusByType[].sections[].menus',
          );
          final menuItems = <MealMenuItem>[];
          for (final menuValue in menus) {
            final menuJson = _requiredMap(
              menuValue,
              'data[].meals[].menusByType[].sections[].menus[]',
            );
            menuItems.add(
              MealMenuItem(
                ko: _requiredString(
                  menuJson['ko'],
                  'data[].meals[].menusByType[].sections[].menus[].ko',
                ),
                en: _nullableString(
                  menuJson['en'],
                  'data[].meals[].menusByType[].sections[].menus[].en',
                ),
              ),
            );
          }

          if (menuItems.isEmpty) {
            continue;
          }
          mealSections.add(
            MealSection(
              type: sectionType,
              title: _nullableMealSectionTitle(sectionJson['sectionTitle']),
              menu: menuItems,
              kcal: calorie is num ? calorie.toInt() : null,
            ),
          );
        }

        if (mealSections.isEmpty) {
          continue;
        }

        switch (menuType) {
          case "KOREAN":
            cafeteriaMeals.add(KoreanMeal(sections: mealSections));
          case "HALAL":
            cafeteriaMeals.add(HalalMeal(sections: mealSections));
          default:
            cafeteriaMeals.add(Meal(sections: mealSections));
        }
      }
    }
  }

  return weekMeal;
}

class WeekMeta {
  final DateTime startDate;
  final bool isCurrentWeek;
  final String? nextWeekStart;

  const WeekMeta({
    required this.startDate,
    required this.isCurrentWeek,
    required this.nextWeekStart,
  });
}

WeekMeta parseWeekMeta(String jsonStr) {
  final root = _requiredMap(jsonDecode(jsonStr), 'root');
  final weekJson = _requiredMap(root['week'], 'week');
  return WeekMeta(
    startDate: DateTime.parse(
      _requiredString(weekJson['startDate'], 'week.startDate'),
    ),
    isCurrentWeek: _requiredBool(
      weekJson['isCurrentWeek'],
      'week.isCurrentWeek',
    ),
    nextWeekStart: _nullableString(
      weekJson['nextWeekStart'],
      'week.nextWeekStart',
    ),
  );
}

Map<String, dynamic> _requiredMap(Object? value, String fieldName) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('$fieldName 필드는 object여야 합니다.');
}

List<dynamic> _requiredList(Object? value, String fieldName) {
  if (value is List<dynamic>) {
    return value;
  }
  throw FormatException('$fieldName 필드는 array여야 합니다.');
}

String _requiredString(Object? value, String fieldName) {
  if (value is String) {
    return value;
  }
  throw FormatException('$fieldName 필드는 string이어야 합니다.');
}

String? _nullableString(Object? value, String fieldName) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('$fieldName 필드는 string 또는 null이어야 합니다.');
}

MealSectionTitle? _nullableMealSectionTitle(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  final ko = value['ko'];
  if (ko is! String || ko.trim().isEmpty) {
    return null;
  }
  final en = value['en'];
  return MealSectionTitle(
    ko: ko.trim(),
    en: en is String && en.trim().isNotEmpty ? en.trim() : null,
  );
}

bool _requiredBool(Object? value, String fieldName) {
  if (value is bool) {
    return value;
  }
  throw FormatException('$fieldName 필드는 boolean이어야 합니다.');
}

class MealMenuItem {
  final String ko;
  final String? en;

  const MealMenuItem({required this.ko, this.en});

  String textFor(String languageCode) =>
      _localizedTextFor(ko, en, languageCode);
}

enum MealSectionType {
  regular('REGULAR'),
  salad('SALAD'),
  convenience('CONVENIENCE'),
  special('SPECIAL');

  final String apiKey;
  const MealSectionType(this.apiKey);

  static MealSectionType? fromApiKey(String key) {
    for (final type in values) {
      if (type.apiKey == key) return type;
    }
    return null;
  }
}

class MealSectionTitle {
  final String ko;
  final String? en;

  const MealSectionTitle({required this.ko, this.en});

  String textFor(String languageCode) =>
      _localizedTextFor(ko, en, languageCode);
}

String _localizedTextFor(String ko, String? en, String languageCode) {
  if (languageCode == 'en' && en != null && en.isNotEmpty) {
    return en;
  }
  return ko;
}

class MealSection {
  final MealSectionType type;
  final MealSectionTitle? title;
  final List<MealMenuItem> menu;
  final int? kcal;

  const MealSection({
    required this.type,
    required this.menu,
    this.title,
    this.kcal,
  });

  String? titleFor(
    String languageCode, {
    required String convenienceLabel,
    required String specialLabel,
  }) {
    final sectionTitle = title;
    if (sectionTitle != null) {
      return sectionTitle.textFor(languageCode);
    }
    return switch (type) {
      MealSectionType.regular || MealSectionType.salad => null,
      MealSectionType.convenience => convenienceLabel,
      MealSectionType.special => specialLabel,
    };
  }
}

class Meal {
  final List<MealSection> sections;

  const Meal({required this.sections});

  factory Meal.regular({
    required List<MealMenuItem> menu,
    int? kcal,
    MealSectionTitle? title,
  }) {
    return Meal(
      sections: [
        MealSection(
          type: MealSectionType.regular,
          title: title,
          menu: menu,
          kcal: kcal,
        ),
      ],
    );
  }

  List<String> localizedMenu(String languageCode) {
    return sections
        .expand((section) => section.menu)
        .map((item) => item.textFor(languageCode))
        .toList(growable: false);
  }

  int? get kcal {
    final regularSections = sections
        .where((section) => section.type == MealSectionType.regular)
        .toList(growable: false);
    return regularSections.length == 1 ? regularSections.single.kcal : null;
  }
}

class KoreanMeal extends Meal {
  const KoreanMeal({required super.sections});
}

class HalalMeal extends Meal {
  const HalalMeal({required super.sections});
}

enum Cafeteria {
  dormitory('DORMITORY'),
  student('STUDENT'),
  faculty('FACULTY');

  final String apiKey;
  const Cafeteria(this.apiKey);

  static Cafeteria fromApiKey(String key) => values.firstWhere(
    (e) => e.apiKey == key,
    orElse: () => throw FormatException('알 수 없는 cafeteria: $key'),
  );
}

class CafeteriaMeal {
  final List<List<Meal>> _cafeterias;

  CafeteriaMeal._(this._cafeterias)
    : assert(_cafeterias.length == Cafeteria.values.length);

  factory CafeteriaMeal.empty() =>
      CafeteriaMeal._(List.generate(Cafeteria.values.length, (_) => <Meal>[]));

  List<Meal> operator [](Cafeteria c) => _cafeterias[c.index];
  List<Meal> fromCafeteria(Cafeteria c) => _cafeterias[c.index];
}

enum MealOfDay {
  breakfast('BREAKFAST'),
  lunch('LUNCH'),
  dinner('DINNER');

  final String apiKey;
  const MealOfDay(this.apiKey);

  MealOfDay get next => values[(index + 1) % values.length];

  static MealOfDay fromApiKey(String key) => values.firstWhere(
    (e) => e.apiKey == key,
    orElse: () => throw FormatException('알 수 없는 mealType: $key'),
  );
}

class DayMeal {
  final List<CafeteriaMeal> _meals;

  DayMeal._(this._meals) : assert(_meals.length == MealOfDay.values.length);

  factory DayMeal.empty() => DayMeal._(
    List.generate(MealOfDay.values.length, (_) => CafeteriaMeal.empty()),
  );

  CafeteriaMeal operator [](MealOfDay m) => _meals[m.index];
  CafeteriaMeal fromMealOfDay(MealOfDay m) => _meals[m.index];
}

enum DayOfWeek {
  mon('MON'),
  tue('TUE'),
  wed('WED'),
  thu('THU'),
  fri('FRI'),
  sat('SAT'),
  sun('SUN');

  final String apiKey;
  const DayOfWeek(this.apiKey);

  DayOfWeek get next => values[(index + 1) % values.length];

  static DayOfWeek fromApiKey(String key) => values.firstWhere(
    (e) => e.apiKey == key,
    orElse: () => throw FormatException('알 수 없는 dayOfWeek: $key'),
  );
}

class WeekMeal {
  final List<DayMeal> _days;

  WeekMeal._(this._days) : assert(_days.length == DayOfWeek.values.length);

  factory WeekMeal.empty() => WeekMeal._(
    List.generate(DayOfWeek.values.length, (_) => DayMeal.empty()),
  );

  DayMeal operator [](DayOfWeek d) => _days[d.index];
  DayMeal fromDayOfWeek(DayOfWeek d) => _days[d.index];
}
