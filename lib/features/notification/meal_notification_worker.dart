import 'dart:ui';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/core/enum_utils.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/info_refresh_service.dart';
import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/meal/meal_refresh_service.dart';
import 'package:meal_client/features/settings/notification/notification_settings.dart'
    show DormMealType;
import 'package:meal_client/features/widget/widget_service.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'meal_notification_period.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';

typedef BackgroundCacheRefresh = Future<void> Function();

/// 디버그 빌드에서 UI의 테스트 버튼이 호출하는 함수.
/// 백그라운드 태스크와 동일한 로직을 메인 isolate에서 즉시 실행한다.
/// [keywordsOverride]를 전달하면 SharedPreferences 값 대신 그 키워드 리스트로
/// 검사한다. (UI에서 막 입력한 값이 prefs에 아직 안 들어간 경우 활용)
Future<void> testMealKeywordCheck({
  List<String>? keywordsOverride,
  MealNotificationPeriod period = MealNotificationPeriod.lunch,
}) => _runMealKeywordCheck(
  period: period,
  targetDate: notificationTargetDateFor(period, DateTime.now()),
  keywordsOverride: keywordsOverride,
  checkDay: false, // 테스트는 요일 필터 무시하고 매칭 로직만 확인
);

/// Workmanager 백그라운드 격리체(isolate) 진입점.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    if (taskName == mealRefreshTaskName ||
        taskName == Workmanager.iOSBackgroundTask) {
      return refreshBackgroundMealAndInfoCaches();
    }

    final period = periodFromTaskName(taskName);
    if (period != null) {
      try {
        await handleKeywordNotificationTask(
          period: period,
          targetDateInput: inputData?['targetDate'],
        );
      } catch (e, stackTrace) {
        debugPrint('[BapU] keyword notification worker failed: $e');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }
    }
    return true;
  });
}

typedef MealKeywordCheckRunner =
    Future<void> Function(MealNotificationPeriod period, DateTime targetDate);
typedef KeywordNotificationRescheduler =
    Future<void> Function(MealNotificationPeriod period);

/// Workmanager 태스크의 저장된 메뉴 대상 날짜를 처리하고 다음 작업을 예약한다.
///
/// 이전 버전이 만든 태스크에는 대상 날짜가 없으므로 검사하지 않고 다음 작업만
/// 새 형식으로 예약한다. 지연 실행 시 실제 실행 시각으로 대상을 다시 계산하면
/// 일요일 밤 알림이 화요일 메뉴를 검사할 수 있기 때문이다.
Future<void> handleKeywordNotificationTask({
  required MealNotificationPeriod period,
  required Object? targetDateInput,
  MealKeywordCheckRunner? runCheck,
  KeywordNotificationRescheduler? reschedule,
}) async {
  final targetDate = notificationTargetDateFromString(targetDateInput);
  if (targetDate == null) {
    debugPrint('[BapU] legacy keyword notification task skipped');
  } else {
    await (runCheck ??
        (period, targetDate) => _runMealKeywordCheck(
          period: period,
          targetDate: targetDate,
        ))(period, targetDate);
  }
  await (reschedule ?? _rescheduleForNextDay)(period);
}

Future<bool> refreshBackgroundMealAndInfoCaches({
  BackgroundCacheRefresh? refreshMealCache,
  BackgroundCacheRefresh? refreshInfoCache,
  BackgroundCacheRefresh? refreshWidget,
}) async {
  final mealRefresh =
      refreshMealCache ??
      () async {
        await MealRefreshService(
          throwOnCacheWriteFailure: true,
        ).refreshMealData(waitForNextWeekPrefetch: true);
      };
  final infoRefresh =
      refreshInfoCache ??
      () async {
        await InfoRefreshService(throwOnCacheWriteFailure: true).refreshInfo();
      };

  final failures = await Future.wait([
    _captureBackgroundRefreshFailure('meal', mealRefresh),
    _captureBackgroundRefreshFailure('info', infoRefresh),
  ]);

  final mealFailure = failures[0];
  if (mealFailure != null) {
    _logBackgroundRefreshFailure('background meal refresh failed', mealFailure);
    return false;
  }

  final infoFailure = failures[1];
  if (infoFailure != null) {
    if (infoFailure.error is InfoCacheWriteException) {
      _logBackgroundRefreshFailure(
        'background info cache write failed',
        infoFailure,
      );
      return false;
    }

    // develop-widget 병합 시에도 notification 브랜치의 기준은 유지한다.
    // meal cache 갱신이 끝난 뒤 /v2/info fetch/parse 실패만으로는 키워드 알림용
    // background task를 실패시키지 않는다. 공유 cache write 실패만 strict 처리한다.
    _logBackgroundRefreshFailure(
      'background info refresh skipped',
      infoFailure,
    );
  }

  final widgetFailure = await _captureBackgroundRefreshFailure(
    'widget',
    refreshWidget ?? () => refreshWidgets(throwOnFailure: true),
  );
  if (widgetFailure != null) {
    _logBackgroundRefreshFailure(
      'background widget refresh failed',
      widgetFailure,
    );
    return false;
  }

  return true;
}

Future<_BackgroundRefreshFailure?> _captureBackgroundRefreshFailure(
  String label,
  BackgroundCacheRefresh refresh,
) async {
  try {
    await refresh();
    return null;
  } catch (e, stackTrace) {
    return _BackgroundRefreshFailure(label, e, stackTrace);
  }
}

void _logBackgroundRefreshFailure(
  String message,
  _BackgroundRefreshFailure failure,
) {
  debugPrint('[BapU] $message (${failure.label}): ${failure.error}');
  debugPrintStack(stackTrace: failure.stackTrace);
}

class _BackgroundRefreshFailure {
  const _BackgroundRefreshFailure(this.label, this.error, this.stackTrace);

  final String label;
  final Object error;
  final StackTrace stackTrace;
}

Future<void> _rescheduleForNextDay(MealNotificationPeriod period) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(StorageKeys.notificationEnabled) ?? false;
  if (!enabled) return;

  final key = '${StorageKeys.notificationPeriodTimePrefix}${period.name}';
  final stored = prefs.getString(key);
  if (stored == null) return; // 이 시간대가 꺼졌으면 재등록 안 함

  final parts = stored.split(':');
  if (parts.length < 2) return;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return;

  final enabledDays = _loadNotificationDays(prefs);
  if (enabledDays.isEmpty) return;

  assert(() {
    debugPrint(
      '[BapU] worker: rescheduling ${period.name} for next day at $hour:$minute',
    );
    return true;
  }());
  await scheduleKeywordNotificationFor(
    period,
    TimeOfDay(hour: hour, minute: minute),
    enabledDays,
  );
  assert(() {
    debugPrint('[BapU] worker: reschedule call completed');
    return true;
  }());
}

Future<void> _runMealKeywordCheck({
  required MealNotificationPeriod period,
  required DateTime targetDate,
  List<String>? keywordsOverride,
  bool checkDay = true,
}) async {
  final prefs = await SharedPreferences.getInstance();

  final enabled = prefs.getBool(StorageKeys.notificationEnabled) ?? false;
  if (!enabled) return;

  final now = DateTime.now();
  if (isNotificationTargetInPast(targetDate, now)) return;
  final targetDay = DayOfWeek.values[targetDate.weekday - 1];

  // 요일 (키가 없으면 모든 요일이 기본값)
  if (checkDay && !_loadNotificationDays(prefs).contains(targetDay)) return;

  // 키워드 로드 (override 또는 prefs). 공백 제거 + 빈 항목 제외.
  // 키워드 필터는 배포 전까지 디버그 빌드에서만 사용한다. 릴리스에서는
  // 이전 디버그 설치의 저장값이 남아 있어도 전체 메뉴 알림으로 동작한다.
  final rawKeywords = kDebugMode
      ? keywordsOverride ??
            prefs.getStringList(StorageKeys.notificationKeywords) ??
            const <String>[]
      : const <String>[];
  final keywords = rawKeywords
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty)
      .toList(growable: false);
  // 기숙사 식당의 알림 대상 여부는 dormMealTypes 하나로만 판단한다.
  // dormMealTypes 키가 아직 없는(=이 기능 이전) 저장값이라면, 구버전에서
  // 기숙사가 선택돼 있었는지로 기본값을 정해 기존 사용자의 동작을 유지한다.
  final cafeteriaNames = prefs.getStringList(
    StorageKeys.notificationCafeterias,
  );
  final storedCafeterias = cafeteriaNames == null
      ? const <Cafeteria>{Cafeteria.dormitory}
      : enumSetFromNames(cafeteriaNames, Cafeteria.values);
  final hadDormitoryBefore = storedCafeterias.contains(Cafeteria.dormitory);
  final otherCafeterias = storedCafeterias
      .where((c) => c != Cafeteria.dormitory)
      .toSet();

  final dormMealTypeNames = prefs.getStringList(
    StorageKeys.notificationDormMealTypes,
  );
  final dormMealTypes = dormMealTypeNames != null
      ? enumSetFromNames(dormMealTypeNames, DormMealType.values)
      : (hadDormitoryBefore
            ? const {DormMealType.korean, DormMealType.halal}
            : const <DormMealType>{});

  final cafeterias = {
    if (dormMealTypes.isNotEmpty) Cafeteria.dormitory,
    ...otherCafeterias,
  };
  if (cafeterias.isEmpty) return;

  final WeekMeal weekMeal;
  try {
    weekMeal = await loadMealForNotificationTarget(
      targetDate: targetDate,
      now: now,
    );
  } catch (_) {
    return;
  }

  final contents = _buildMealNotificationContents(
    weekMeal: weekMeal,
    targetDate: targetDate,
    period: period,
    cafeterias: cafeterias,
    dormMealTypes: dormMealTypes,
    keywords: keywords,
    l10n: notificationLocalizations(),
  );
  if (contents.isEmpty) return;

  await initNotifications();
  for (final content in contents) {
    await showMealNotification(
      id: content.id,
      title: content.title,
      body: content.body,
    );
  }
}

typedef _MealNotificationContent = ({int id, String title, String body});
typedef _NotificationMealGroup = ({int id, List<Meal> meals});

/// 키워드가 없으면 선택한 식당의 전체 메뉴를, 있으면 매칭 결과를 만든다.
List<_MealNotificationContent> _buildMealNotificationContents({
  required WeekMeal weekMeal,
  required DateTime targetDate,
  required MealNotificationPeriod period,
  required Set<Cafeteria> cafeterias,
  required Set<DormMealType> dormMealTypes,
  required List<String> keywords,
  required AppLocalizations l10n,
}) {
  final mealsByLabel = <String, _NotificationMealGroup>{};
  for (final cafeteria in Cafeteria.values.where(cafeterias.contains)) {
    final meals = mealsForNotificationTarget(
      weekMeal: weekMeal,
      targetDate: targetDate,
      period: period,
      cafeteria: cafeteria,
    );
    for (final meal in meals) {
      final String label;
      final int notificationId;
      if (cafeteria == Cafeteria.dormitory) {
        if (meal is KoreanMeal) {
          if (!dormMealTypes.contains(DormMealType.korean)) continue;
          label = l10n.cafeteriaWithMealType(
            l10n.dormitoryCafeteria,
            l10n.menuKorean,
          );
          notificationId = 1;
        } else if (meal is HalalMeal) {
          if (!dormMealTypes.contains(DormMealType.halal)) continue;
          label = l10n.cafeteriaWithMealType(
            l10n.dormitoryCafeteria,
            l10n.menuHalal,
          );
          notificationId = 2;
        } else {
          label = l10n.dormitoryCafeteria;
          notificationId = 3;
        }
      } else {
        label = switch (cafeteria) {
          Cafeteria.dormitory => l10n.dormitoryCafeteria, // unreachable
          Cafeteria.student => l10n.studentCafeteria,
          Cafeteria.faculty => l10n.facultyCafeteria,
        };
        notificationId = switch (cafeteria) {
          Cafeteria.dormitory => 3, // unreachable
          Cafeteria.student => 4,
          Cafeteria.faculty => 5,
        };
      }
      mealsByLabel
          .putIfAbsent(label, () => (id: notificationId, meals: <Meal>[]))
          .meals
          .add(meal);
    }
  }

  final periodLabel = _periodLabel(period, l10n);
  if (keywords.isEmpty) {
    final contents = <_MealNotificationContent>[];
    for (final entry in mealsByLabel.entries) {
      final items = <String>{
        for (final meal in entry.value.meals)
          ..._notificationMenuItems(meal, l10n.localeName),
      }.toList(growable: false);
      if (items.isEmpty) continue;
      contents.add((
        id: entry.value.id,
        title: l10n.mealNotificationTitle(
          entry.key,
          _mealOfDayLabel(period, l10n),
        ),
        body: items.join(' / '),
      ));
    }
    return contents;
  }

  // 키워드별 매칭 결과: { "떡갈비" -> ["기숙사 한식"], "국" -> [...] }
  final matchesByKeyword = <String, List<String>>{};
  for (final keyword in keywords) {
    final keywordLower = keyword.toLowerCase();
    final matches = <String>[];
    for (final entry in mealsByLabel.entries) {
      if (entry.value.meals.any(
        (meal) => mealContainsKeyword(meal, keywordLower),
      )) {
        matches.add(entry.key);
      }
    }

    if (matches.isNotEmpty) {
      matchesByKeyword[keyword] = matches;
    }
  }

  if (matchesByKeyword.isEmpty) return const [];

  final String title;
  final String body;
  if (matchesByKeyword.length == 1) {
    final entry = matchesByKeyword.entries.first;
    title = l10n.keywordMealNotificationTitle(periodLabel, entry.key);
    body = entry.value.join(', ');
  } else {
    title = l10n.multipleKeywordMealNotificationTitle(periodLabel);
    body = matchesByKeyword.entries
        .map((e) => '"${e.key}": ${e.value.join(', ')}')
        .join('\n');
  }

  return [(id: 9, title: title, body: body)];
}

Iterable<String> _notificationMenuItems(Meal meal, String languageCode) => meal
    .sections
    .where((section) => section.type != MealSectionType.salad)
    .expand((section) => section.menu)
    .map((item) => item.textFor(languageCode).trim())
    .where((item) => item.isNotEmpty);

/// [targetDate]가 현재 KST 날짜보다 이전인지 반환한다.
bool isNotificationTargetInPast(DateTime targetDate, DateTime now) {
  return targetDate.isBefore(kstCalendarDate(now));
}

typedef CurrentWeekMealLoader = Future<WeekMeal> Function();
typedef DatedWeekMealLoader = Future<WeekMeal> Function(String weekStart);

/// 대상 날짜가 현재 주면 기존 캐시 경로를, 아니면 날짜 지정 API를 사용한다.
///
/// 날짜 지정 API 결과는 현재 주 캐시에 쓰지 않아 일요일의 다음 주 조회가
/// `meal.json`을 덮어쓰지 않는다.
Future<WeekMeal> loadMealForNotificationTarget({
  required DateTime targetDate,
  required DateTime now,
  CurrentWeekMealLoader? loadCurrentWeek,
  DatedWeekMealLoader? loadDatedWeek,
}) {
  final targetWeekStart = kstWeekStartFromDate(targetDate);
  final currentWeekStart = kstWeekStartFromDate(kstCalendarDate(now));
  if (targetWeekStart == currentWeekStart) {
    return (loadCurrentWeek ??
        () => MealRefreshService().getFreshOrRefreshMealData())();
  }

  return (loadDatedWeek ?? fetchMealDataForWeek)(
    notificationTargetDateString(targetWeekStart),
  );
}

/// 주차 조회 결과에서 저장된 메뉴 대상 날짜의 식단만 꺼낸다.
List<Meal> mealsForNotificationTarget({
  required WeekMeal weekMeal,
  required DateTime targetDate,
  required MealNotificationPeriod period,
  required Cafeteria cafeteria,
}) {
  final targetDay = DayOfWeek.values[targetDate.weekday - 1];
  return weekMeal[targetDay][period.mealOfDay][cafeteria];
}

/// 알림 대상 섹션의 한글/영문 메뉴에서 소문자 키워드를 찾는다.
bool mealContainsKeyword(Meal meal, String keywordLower) {
  return meal.sections
      .where((section) => section.type != MealSectionType.salad)
      .expand((section) => section.menu)
      .any(
        (item) =>
            item.ko.toLowerCase().contains(keywordLower) ||
            (item.en?.toLowerCase().contains(keywordLower) ?? false),
      );
}

Set<DayOfWeek> _loadNotificationDays(SharedPreferences prefs) {
  return notificationDaysFromNames(
    prefs.getStringList(StorageKeys.notificationDays),
  );
}

String _periodLabel(MealNotificationPeriod period, AppLocalizations l10n) =>
    switch (period) {
      MealNotificationPeriod.morning => l10n.notificationTodayBreakfast,
      MealNotificationPeriod.lunch => l10n.notificationTodayLunch,
      MealNotificationPeriod.dinner => l10n.notificationTodayDinner,
      MealNotificationPeriod.night => l10n.notificationTomorrowBreakfast,
    };

String _mealOfDayLabel(MealNotificationPeriod period, AppLocalizations l10n) =>
    switch (period) {
      MealNotificationPeriod.morning ||
      MealNotificationPeriod.night => l10n.breakfast,
      MealNotificationPeriod.lunch => l10n.lunch,
      MealNotificationPeriod.dinner => l10n.dinner,
    };
