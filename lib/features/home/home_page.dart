import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/info/announcement_state.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_data_source.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/widget/widget_service.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'home_drawer.dart';
import 'week_menu_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DateTime _mondayOfWeek;
  late final DayOfWeek _initialDayOfWeek;
  late final MealOfDay _initialMealOfDay;

  late final Future<WeekMeal> cachedMeal;
  late final Future<WeekMeal> downloadedMeal;
  late final Future<String?> nextWeekStart;
  late final Future<AppInfo> appInfo;

  @override
  void initState() {
    super.initState();
    _initializeModelAndDate();
    _initializeDataLoading();
    appInfo = fetchAppInfo();
    _checkAnnouncement();
  }

  void _initializeModelAndDate() {
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    _initialMealOfDay = MealTimeConfig.determineMealOfDay(kstNow);
    _initialDayOfWeek = DayOfWeek.values[kstNow.weekday - 1];
    _mondayOfWeek = kstNow.subtract(Duration(days: kstNow.weekday - 1));
  }

  void _initializeDataLoading() {
    final cachedMealRecord = getCachedMealData();
    final downloadedMealRecord = cachedMealRecord
        .then(
          (_) => fetchAndCacheMealData(),
          onError: (e) => fetchAndCacheMealData(),
        )
        .then((meal) {
          updateHomeWidgets();
          return meal;
        })
        .catchError((e) {
          assert(() {
            debugPrint('[BapU] meal fetch failed: $e');
            return true;
          }());
          throw e;
        });

    cachedMeal = cachedMealRecord.then((r) => r.weekMeal);
    downloadedMeal = downloadedMealRecord.then((r) => r.weekMeal);
    // 캐시(getCachedMealData)의 신선도 검증은 주차 번호만 비교하므로,
    // 같은 주 안에서 nextWeekStart가 null → 날짜로 바뀌는 변화를 감지하지
    // 못한다. 반드시 매번 새로 받아오는 downloadedMealRecord 기준으로
    // nextWeekStart를 뽑는다 (docs/superpowers/specs/
    // 2026-07-07-next-week-preview-design.md 참고).
    nextWeekStart = downloadedMealRecord
        .then<String?>((r) => r.weekMeta.nextWeekStart)
        .catchError((e) => null);
  }

  void _checkAnnouncement() {
    checkForNewAnnouncement(loadInfo: () => appInfo)
        .then((announcement) {
          if (announcement != null && mounted) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _showAnnouncementDialog(announcement);
            });
          }
        })
        .catchError((e) {
          assert(() {
            debugPrint('[BapU] announcement fetch failed: $e');
            return true;
          }());
        });
  }

  @override
  Widget build(BuildContext context) {
    return WeekMenuScaffold(
      mondayOfWeek: _mondayOfWeek,
      initialDayOfWeek: _initialDayOfWeek,
      initialMealOfDay: _initialMealOfDay,
      cachedMealFuture: cachedMeal,
      mealFuture: downloadedMeal,
      appInfo: appInfo,
      drawer: HomePageDrawer(infoFuture: appInfo, nextWeekStart: nextWeekStart),
    );
  }

  void _showAnnouncementDialog(AppAnnouncement announcement) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final languageCode = Localizations.localeOf(context).languageCode;
        return HomeAnnouncementDialog(
          close: l10n.close,
          title: announcement.title?.textFor(languageCode) ?? l10n.announcement,
          content: announcement.content.textFor(languageCode),
        );
      },
    );
  }
}
