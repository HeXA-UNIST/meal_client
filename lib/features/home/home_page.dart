import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/info/announcement_state.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_data_source.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/widget/widget_service.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'home_drawer.dart';
import 'week_menu_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.now,
    this.loadAppInfo,
    this.loadCachedMeal,
    this.refreshMeal,
    this.refreshHomeWidgets,
  });

  /// 위젯 테스트에서 KST 주 경계를 재현하기 위한 시계 주입점.
  final DateTime Function()? now;

  /// 위젯 테스트에서 네트워크 없이 안내 정보를 제공하기 위한 주입점.
  final Future<AppInfo> Function()? loadAppInfo;

  /// 위젯 테스트에서 캐시 식단 로딩 순서를 제어하기 위한 주입점.
  final Future<MealResponse> Function()? loadCachedMeal;

  /// 위젯 테스트에서 새 식단 갱신 순서를 제어하기 위한 주입점.
  final Future<MealResponse> Function()? refreshMeal;

  /// 위젯 테스트에서 홈 화면 위젯 갱신을 대체하기 위한 주입점.
  final Future<void> Function()? refreshHomeWidgets;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late DateTime _mondayOfWeek;
  late DayOfWeek _initialDayOfWeek;
  late MealOfDay _initialMealOfDay;
  late int _weekId;

  late Future<WeekMeal> cachedMeal;
  late Future<WeekMeal> downloadedMeal;
  late Future<String?> nextWeekStart;
  late final Future<AppInfo> appInfo;
  Future<void> _mealRefreshQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeModelAndDate();
    _initializeDataLoading();
    appInfo = (widget.loadAppInfo ?? fetchAppInfo)();
    _checkAnnouncement();
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  void _initializeModelAndDate([DateTime? now]) {
    final instant = now ?? _now();
    final kstNow = MealTimeConfig.toKst(instant);
    _weekId = MealTimeConfig.kstWeekId(instant);
    _initialMealOfDay = MealTimeConfig.determineMealOfDay(kstNow);
    _initialDayOfWeek = DayOfWeek.values[kstNow.weekday - 1];
    _mondayOfWeek = DateTime.utc(
      kstNow.year,
      kstNow.month,
      kstNow.day,
    ).subtract(Duration(days: kstNow.weekday - 1));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    final now = _now();
    if (_weekId == MealTimeConfig.kstWeekId(now)) {
      return;
    }

    setState(() {
      _initializeModelAndDate(now);
      _initializeDataLoading();
    });
  }

  void _initializeDataLoading() {
    final cachedMealRecord = (widget.loadCachedMeal ?? getCachedMealData)();
    final downloadedMealRecord = _enqueueMealRefresh(cachedMealRecord)
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

  /// 주차 전환 전후의 갱신이 canonical meal.json을 역순으로 쓰지 않게 한다.
  ///
  /// 캐시 확인부터 갱신까지를 초기화 순서대로 직렬화하므로, 월요일 갱신은
  /// 아직 끝나지 않은 일요일 갱신의 저장·위젯 렌더 뒤에 실행된다.
  Future<MealResponse> _enqueueMealRefresh(
    Future<MealResponse> cachedMealRecord,
  ) {
    final refreshMeal =
        widget.refreshMeal ??
        () {
          final now = _now();
          return fetchAndCacheCanonicalMealData(
            now: now,
            waitForNextWeekPrefetch:
                mealNotificationPlatform == MealNotificationPlatform.ios &&
                MealTimeConfig.toKst(now).weekday == DateTime.sunday,
          );
        };
    final queuedRefresh = _mealRefreshQueue.then((_) async {
      try {
        await cachedMealRecord;
      } catch (_) {
        // 캐시 실패는 기존 동작처럼 네트워크 갱신으로 복구한다.
      }
      final meal = await refreshMeal();
      await (widget.refreshHomeWidgets ?? updateHomeWidgets)();
      if (mounted) {
        Provider.of<AppSettings?>(
          context,
          listen: false,
        )?.reconcileIosMealNotificationsAfterForegroundRefresh();
      }
      return meal;
    });
    _mealRefreshQueue = queuedRefresh.then<void>((_) {}, onError: (_, _) {});
    return queuedRefresh;
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
      key: ValueKey(_mondayOfWeek),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
