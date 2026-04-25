import 'package:meal_client/meal.dart';

class WidgetSettings {
  final Cafeteria cafeteria;
  final MealOfDay mealOfDay;

  const WidgetSettings({
    this.cafeteria = Cafeteria.dormitory,
    this.mealOfDay = MealOfDay.lunch,
  });

  WidgetSettings copyWith({Cafeteria? cafeteria, MealOfDay? mealOfDay}) =>
      WidgetSettings(
        cafeteria: cafeteria ?? this.cafeteria,
        mealOfDay: mealOfDay ?? this.mealOfDay,
      );

  WidgetSettings reset() => const WidgetSettings();
}
