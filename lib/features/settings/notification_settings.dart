import 'package:flutter/material.dart';
import 'package:meal_client/domain/meal.dart';

class NotificationSettings {
  final bool enabled;
  final List<String> keywords;
  final TimeOfDay alertTime;
  final Set<Cafeteria> cafeterias;

  NotificationSettings({
    this.enabled = false,
    List<String> keywords = const [],
    this.alertTime = const TimeOfDay(hour: 8, minute: 0),
    Set<Cafeteria> cafeterias = const {Cafeteria.dormitory},
  })  : keywords = List.unmodifiable(keywords),
        cafeterias = Set.unmodifiable(cafeterias);

  NotificationSettings copyWith({
    bool? enabled,
    List<String>? keywords,
    TimeOfDay? alertTime,
    Set<Cafeteria>? cafeterias,
  }) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        keywords: keywords ?? this.keywords,
        alertTime: alertTime ?? this.alertTime,
        cafeterias: cafeterias ?? this.cafeterias,
      );

  NotificationSettings reset() => NotificationSettings();
}
