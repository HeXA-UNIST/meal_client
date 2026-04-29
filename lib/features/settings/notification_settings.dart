import 'package:flutter/material.dart';
import 'package:meal_client/domain/meal.dart';

class NotificationSettings {
  final bool enabled;
  final String keyword;
  final TimeOfDay alertTime;
  final Set<Cafeteria> cafeterias;

  NotificationSettings({
    this.enabled = false,
    this.keyword = '',
    this.alertTime = const TimeOfDay(hour: 8, minute: 0),
    Set<Cafeteria> cafeterias = const {Cafeteria.dormitory},
  }) : cafeterias = Set.unmodifiable(cafeterias);

  NotificationSettings copyWith({
    bool? enabled,
    String? keyword,
    TimeOfDay? alertTime,
    Set<Cafeteria>? cafeterias,
  }) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        keyword: keyword ?? this.keyword,
        alertTime: alertTime ?? this.alertTime,
        cafeterias: cafeterias ?? this.cafeterias,
      );

  NotificationSettings reset() => NotificationSettings();
}
