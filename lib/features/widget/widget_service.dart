import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/domain/meal.dart';

/// 홈 화면 위젯에 오늘의 식단 데이터를 저장하고 업데이트를 트리거한다.
Future<void> updateHomeWidgets(WeekMeal weekMeal) async {
  if (kIsWeb) return;
  if (!Platform.isAndroid && !Platform.isIOS) return;

  try {
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final dayOfWeek = DayOfWeek.values[kstNow.weekday - 1];
    final mealOfDay = MealTimeConfig.determineMealOfDay(kstNow);

    final dayMeal = weekMeal[dayOfWeek];
    final cafMeal = dayMeal[mealOfDay];

    // 기숙사: 한식/할랄 분리
    final dormMeals = cafMeal[Cafeteria.dormitory];
    KoreanMeal? dormKorean;
    HalalMeal? dormHalal;
    for (final m in dormMeals) {
      if (m is KoreanMeal) dormKorean ??= m;
      if (m is HalalMeal) dormHalal ??= m;
    }

    // 학생 / 교직원 (Meal 단건)
    final studentMeals = cafMeal[Cafeteria.student];
    final studentMeal = studentMeals.isNotEmpty ? studentMeals.first : null;

    final facultyMeals = cafMeal[Cafeteria.faculty];
    final facultyMeal = facultyMeals.isNotEmpty ? facultyMeals.first : null;

    await Future.wait([
      HomeWidget.saveWidgetData<String>('meal_of_day', mealOfDay.index.toString()),
      // 기숙사 한식
      HomeWidget.saveWidgetData<String>('dorm_korean_menu', _joinMenu(dormKorean?.menu)),
      HomeWidget.saveWidgetData<String>('dorm_korean_kcal', _kcalStr(dormKorean?.kcal)),
      // 기숙사 할랄
      HomeWidget.saveWidgetData<String>('dorm_halal_menu', _joinMenu(dormHalal?.menu)),
      HomeWidget.saveWidgetData<String>('dorm_halal_kcal', _kcalStr(dormHalal?.kcal)),
      // 학생
      HomeWidget.saveWidgetData<String>('student_menu', _joinMenu(studentMeal?.menu)),
      HomeWidget.saveWidgetData<String>('student_kcal', _kcalStr(studentMeal?.kcal)),
      // 교직원
      HomeWidget.saveWidgetData<String>('faculty_menu', _joinMenu(facultyMeal?.menu)),
      HomeWidget.saveWidgetData<String>('faculty_kcal', _kcalStr(facultyMeal?.kcal)),
    ]);

    // 모든 위젯 프로바이더 업데이트 트리거
    if (Platform.isAndroid) {
      const pkg = 'pro.hexa.meal.meal_client';
      await Future.wait([
        HomeWidget.updateWidget(qualifiedAndroidName: '$pkg.BapUWidget2x2Provider'),
        HomeWidget.updateWidget(qualifiedAndroidName: '$pkg.BapUWidget4x2DualProvider'),
        HomeWidget.updateWidget(qualifiedAndroidName: '$pkg.BapUWidget4x2StatusProvider'),
        HomeWidget.updateWidget(qualifiedAndroidName: '$pkg.BapUWidget4x4Provider'),
      ]);
    }
  } catch (e) {
    assert(() {
      debugPrint('[BapU] widget update failed: $e');
      return true;
    }());
  }
}

String _joinMenu(List<String>? menu) => menu?.join('\n') ?? '';
String _kcalStr(int? kcal) => kcal != null && kcal > 0 ? kcal.toString() : '';
