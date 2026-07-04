import 'package:flutter/material.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_alert_period.dart';

class NotificationSettings {
  final bool enabled;
  final List<String> keywords;

  /// 시간대별 알림 시각. 값이 없으면(=키가 없거나 null이면) 그 시간대는 꺼진 상태.
  /// 저장된 TimeOfDay는 해당 시간대 범위 내의 15분 슬롯 중 하나여야 한다.
  final Map<MealAlertPeriod, TimeOfDay?> alertTimes;

  /// 시간대별 "마지막으로 선택한 시각". 시간대를 꺼도 유지되어, 다시 켜거나
  /// 꺼진 상태를 표시할 때 이전 선택값을 복원하는 데 쓴다.
  final Map<MealAlertPeriod, TimeOfDay> rememberedTimes;

  final Set<Cafeteria> cafeterias;

  NotificationSettings({
    this.enabled = false,
    List<String> keywords = const [],
    Map<MealAlertPeriod, TimeOfDay?> alertTimes = const {},
    Map<MealAlertPeriod, TimeOfDay> rememberedTimes = const {},
    Set<Cafeteria> cafeterias = const {Cafeteria.dormitory},
  })  : keywords = List.unmodifiable(keywords),
        alertTimes = Map.unmodifiable(alertTimes),
        rememberedTimes = Map.unmodifiable(rememberedTimes),
        cafeterias = Set.unmodifiable(cafeterias);

  /// 활성화된 시간대 (알림 시각이 설정된 것).
  Iterable<MealAlertPeriod> get activePeriods =>
      alertTimes.entries.where((e) => e.value != null).map((e) => e.key);

  bool isPeriodEnabled(MealAlertPeriod p) => alertTimes[p] != null;
  TimeOfDay? alertTimeOf(MealAlertPeriod p) => alertTimes[p];

  /// 해당 시간대에 표시/복원할 시각. 켜져 있으면 현재 시각, 꺼져 있으면
  /// 마지막으로 선택했던 시각, 그마저 없으면 그 시간대의 기본 슬롯.
  TimeOfDay displayTimeOf(MealAlertPeriod p) =>
      alertTimes[p] ?? rememberedTimes[p] ?? p.defaultSlot;

  NotificationSettings copyWith({
    bool? enabled,
    List<String>? keywords,
    Map<MealAlertPeriod, TimeOfDay?>? alertTimes,
    Map<MealAlertPeriod, TimeOfDay>? rememberedTimes,
    Set<Cafeteria>? cafeterias,
  }) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        keywords: keywords ?? this.keywords,
        alertTimes: alertTimes ?? this.alertTimes,
        rememberedTimes: rememberedTimes ?? this.rememberedTimes,
        cafeterias: cafeterias ?? this.cafeterias,
      );

  NotificationSettings reset() => NotificationSettings();
}
