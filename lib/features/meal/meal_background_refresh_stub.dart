const mealRefreshTaskName = 'bapu_meal_refresh';
const mealRefreshTaskFrequency = Duration(hours: 2);

Future<void> initializeMealBackgroundRefresh() async {}

Future<void> postponeMealBackgroundRefresh() async {}

Future<bool> syncMealBackgroundRefresh({bool updateExisting = false}) async =>
    false;
