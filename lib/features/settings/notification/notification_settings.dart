import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/notification/meal_notification_period.dart';

/// 기숙사 식당 알림 대상 메뉴 종류.
enum DormMenuType { korean, halal }

/// 실제 알림 콘텐츠 생성에 사용하는 정규화된 설정 스냅샷.
class NotificationDeliverySettings {
  NotificationDeliverySettings({
    required Set<Cafeteria> cafeterias,
    required Set<DormMenuType> dormMealTypes,
    required List<String> keywords,
  }) : cafeterias = Set.unmodifiable(cafeterias),
       dormMealTypes = Set.unmodifiable(dormMealTypes),
       keywords = List.unmodifiable(keywords);

  final Set<Cafeteria> cafeterias;
  final Set<DormMenuType> dormMealTypes;
  final List<String> keywords;
}

/// 저장/UI 설정에서 플랫폼 공통 발송 대상을 만든다.
///
/// 키워드 기능이 배포되기 전까지 Release 빌드는 저장된 Debug 키워드를 무시한다.
NotificationDeliverySettings normalizeNotificationDeliverySettings(
  NotificationSettings settings, {
  bool keywordFilterEnabled = kDebugMode,
  List<String>? keywordsOverride,
}) {
  final rawKeywords = keywordFilterEnabled
      ? keywordsOverride ?? settings.keywords
      : const <String>[];
  return NotificationDeliverySettings(
    cafeterias: settings.activeCafeterias,
    dormMealTypes: settings.dormMealTypes,
    keywords: rawKeywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toList(growable: false),
  );
}

class NotificationSettings {
  final bool enabled;
  final List<String> keywords;

  /// 시간대별 알림 시각. 값이 없으면(=키가 없거나 null이면) 그 시간대는 꺼진 상태.
  /// 저장된 TimeOfDay는 해당 시간대 범위 내의 30분 슬롯 중 하나여야 한다.
  final Map<MealNotificationPeriod, TimeOfDay?> alertTimes;

  /// 시간대별 "마지막으로 선택한 시각". 시간대를 꺼도 유지되어, 다시 켜거나
  /// 꺼진 상태를 표시할 때 이전 선택값을 복원하는 데 쓴다.
  final Map<MealNotificationPeriod, TimeOfDay> rememberedTimes;

  /// 학생·교직원 식당 알림 대상. 기숙사 식당은 여기 포함하지 않는다 —
  /// 기숙사 식당의 알림 대상 여부는 [dormMealTypes]가 비어있는지로만 판단한다
  /// (두 값을 동시에 저장하면 서로 어긋날 수 있어, 진실 공급원을 하나로 둔다).
  final Set<Cafeteria> cafeterias;

  /// 기숙사 식당 알림 대상 메뉴 종류(한식/할랄). 기본값은 둘 다.
  /// 비어있으면 기숙사 식당 자체가 알림 대상에서 빠진 것으로 취급한다.
  final Set<DormMenuType> dormMealTypes;

  /// 알림을 받을 요일. 이 집합에 없는 요일에는 알림이 발송되지 않는다.
  /// 기본값은 모든 요일.
  final Set<DayOfWeek> days;

  NotificationSettings({
    this.enabled = false,
    List<String> keywords = const [],
    Map<MealNotificationPeriod, TimeOfDay?> alertTimes = const {},
    Map<MealNotificationPeriod, TimeOfDay> rememberedTimes = const {},
    Set<Cafeteria> cafeterias = const {},
    Set<DormMenuType> dormMealTypes = const {
      DormMenuType.korean,
      DormMenuType.halal,
    },
    Set<DayOfWeek>? days,
  }) : keywords = List.unmodifiable(keywords),
       alertTimes = Map.unmodifiable(alertTimes),
       rememberedTimes = Map.unmodifiable(rememberedTimes),
       cafeterias = Set.unmodifiable(cafeterias),
       dormMealTypes = Set.unmodifiable(dormMealTypes),
       days = Set.unmodifiable(days ?? DayOfWeek.values.toSet());

  /// 활성화된 시간대 (알림 시각이 설정된 것).
  Iterable<MealNotificationPeriod> get activePeriods =>
      alertTimes.entries.where((e) => e.value != null).map((e) => e.key);

  bool isPeriodEnabled(MealNotificationPeriod p) => alertTimes[p] != null;
  TimeOfDay? alertTimeOf(MealNotificationPeriod p) => alertTimes[p];

  /// 해당 시간대에 표시/복원할 시각. 켜져 있으면 현재 시각, 꺼져 있으면
  /// 마지막으로 선택했던 시각, 그마저 없으면 그 시간대의 기본 슬롯.
  TimeOfDay displayTimeOf(MealNotificationPeriod p) =>
      alertTimes[p] ?? rememberedTimes[p] ?? p.defaultSlot;

  bool isDayEnabled(DayOfWeek d) => days.contains(d);

  bool isDormMealTypeEnabled(DormMenuType t) => dormMealTypes.contains(t);

  /// 기숙사 식당(선택된 경우)까지 포함한 실제 알림 대상 식당 집합.
  Set<Cafeteria> get activeCafeterias => {
    if (dormMealTypes.isNotEmpty) Cafeteria.dormitory,
    ...cafeterias,
  };

  NotificationSettings copyWith({
    bool? enabled,
    List<String>? keywords,
    Map<MealNotificationPeriod, TimeOfDay?>? alertTimes,
    Map<MealNotificationPeriod, TimeOfDay>? rememberedTimes,
    Set<Cafeteria>? cafeterias,
    Set<DormMenuType>? dormMealTypes,
    Set<DayOfWeek>? days,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    keywords: keywords ?? this.keywords,
    alertTimes: alertTimes ?? this.alertTimes,
    rememberedTimes: rememberedTimes ?? this.rememberedTimes,
    cafeterias: cafeterias ?? this.cafeterias,
    dormMealTypes: dormMealTypes ?? this.dormMealTypes,
    days: days ?? this.days,
  );

  NotificationSettings reset() => NotificationSettings();
}
