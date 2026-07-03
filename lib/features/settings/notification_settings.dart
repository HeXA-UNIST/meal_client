import 'package:flutter/material.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_alert_period.dart';

class NotificationSettings {
  final bool enabled;
  final List<String> keywords;

  /// 시간대별 알림 시각. 값이 없으면(=키가 없거나 null이면) 그 시간대는 꺼진 상태.
  /// 저장된 TimeOfDay는 해당 시간대 범위 내의 15분 슬롯 중 하나여야 한다.
  final Map<MealAlertPeriod, TimeOfDay?> alertTimes;

  final Set<Cafeteria> cafeterias;

  NotificationSettings({
    this.enabled = false,
    List<String> keywords = const [],
    Map<MealAlertPeriod, TimeOfDay?> alertTimes = const {},
    Set<Cafeteria> cafeterias = const {Cafeteria.dormitory},
  })  : keywords = List.unmodifiable(keywords),
        alertTimes = Map.unmodifiable(alertTimes),
        cafeterias = Set.unmodifiable(cafeterias);

  /// 활성화된 시간대 (알림 시각이 설정된 것).
  Iterable<MealAlertPeriod> get activePeriods =>
      alertTimes.entries.where((e) => e.value != null).map((e) => e.key);

  bool isPeriodEnabled(MealAlertPeriod p) => alertTimes[p] != null;
  TimeOfDay? alertTimeOf(MealAlertPeriod p) => alertTimes[p];

  NotificationSettings copyWith({
    bool? enabled,
    List<String>? keywords,
    Map<MealAlertPeriod, TimeOfDay?>? alertTimes,
    Set<Cafeteria>? cafeterias,
  }) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        keywords: keywords ?? this.keywords,
        alertTimes: alertTimes ?? this.alertTimes,
        cafeterias: cafeterias ?? this.cafeterias,
      );

  NotificationSettings reset() => NotificationSettings();
}
