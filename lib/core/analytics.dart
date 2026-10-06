import 'dart:async' show unawaited;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:meal_client/domain/meal.dart';

enum UiClickTarget {
  dayTab('day_tab'),
  mealSwitch('meal_switch'),
  nextWeek('next_week'),
  operationHours('operation_hours'),
  settings('settings'),
  notificationSettings('notification_settings');

  const UiClickTarget(this.code);
  final String code;
}

enum AnalyticsScreen {
  home('home'),
  nextWeek('next_week'),
  settings('settings');

  const AnalyticsScreen(this.code);
  final String code;
}

// 정해진 항목 코드만 보내고, 전송 실패가 화면 동작에 영향을 주지 않게 한다.
void logUiClick(
  UiClickTarget target, {
  required AnalyticsScreen screen,
  DayOfWeek? dayOfWeek,
  MealOfDay? mealOfDay,
}) {
  unawaited(_recordUiClick(target, screen, dayOfWeek, mealOfDay));
}

Future<void> _recordUiClick(
  UiClickTarget target,
  AnalyticsScreen screen,
  DayOfWeek? dayOfWeek,
  MealOfDay? mealOfDay,
) async {
  try {
    // 테스트와 Web 초기화 이전에는 기록하지 않는다.
    if ((kIsWeb && !kReleaseMode) || Firebase.apps.isEmpty) return;
    final analytics = FirebaseAnalytics.instance;
    if (kIsWeb && !await analytics.isSupported()) return;
    await analytics.logEvent(
      name: 'ui_click',
      parameters: {
        'target': target.code,
        'screen': screen.code,
        if (dayOfWeek != null) 'day_of_week': dayOfWeek.name,
        if (mealOfDay != null) 'meal_of_day': mealOfDay.name,
      },
    );
  } catch (_) {
    debugPrint('클릭 이벤트를 전송하지 못했습니다.');
  }
}
