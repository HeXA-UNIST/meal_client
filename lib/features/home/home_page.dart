import 'dart:async';

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
    this.loadCachedAppInfo,
    this.loadCachedMeal,
    this.refreshMeal,
    this.refreshHomeWidgets,
  });

  /// 위젯 테스트에서 KST 주 경계를 재현하기 위한 시계 주입점.
  final DateTime Function()? now;

  /// 위젯 테스트에서 네트워크 없이 안내 정보를 제공하기 위한 주입점.
  final Future<AppInfo> Function()? loadAppInfo;

  /// 위젯 테스트에서 캐시된 안내 정보를 제공하기 위한 주입점.
  final Future<AppInfo?> Function()? loadCachedAppInfo;

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

  /// 화면 표시용. 캐시가 있으면 그것으로 먼저 완료되고 이후 fresh로 교체된다.
  late Future<AppInfo> appInfo;

  /// 공지 비교 전용. 캐시된 공지로 판단하면 서버의 새 공지가 다음 실행까지
  /// 밀리고, 게다가 캐시 공지의 fingerprint가 저장돼 버린다.
  late final Future<AppInfo> _freshAppInfo;
  Future<void> _mealRefreshQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeModelAndDate();
    _initializeDataLoading();
    _freshAppInfo = _fetchFreshAppInfo();
    appInfo = _loadAppInfo(_freshAppInfo);
    // 화면의 FutureBuilder가 붙기 전에 실패하면 listener가 없어 unhandled async
    // error가 된다. 오류 표시는 그대로 FutureBuilder가 맡고, 여기서는 관찰만 한다.
    unawaited(appInfo.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    _checkAnnouncement();
  }

  /// 캐시된 info.json이 있으면 그것으로 먼저 화면을 채우고, 네트워크 응답이
  /// 도착하면 future를 교체한다. FutureBuilder는 future가 바뀌어도 직전 data를
  /// 유지하므로(`_FutureBuilderState.didUpdateWidget`) 교체 시 깜빡이지 않는다.
  Future<AppInfo> _loadAppInfo(Future<AppInfo> fresh) async {
    // cache를 읽는 사이에 fresh가 먼저 실패하면 listener가 없어 unhandled async
    // error가 된다. 결과 관찰을 곧바로 걸어 두고, 성공 여부만 따로 받는다.
    final freshFailed = fresh.then<bool>(
      (_) => false,
      onError: (Object error, StackTrace _) {
        assert(() {
          debugPrint('[BapU] fresh app info fetch failed: $error');
          return true;
        }());
        return true;
      },
    );
    final cached = await (widget.loadCachedAppInfo ?? readCachedAppInfo)();
    if (cached == null) return fresh;
    unawaited(_replaceAppInfoWithFresh(fresh, freshFailed));
    return cached;
  }

  Future<AppInfo> _fetchFreshAppInfo() async {
    final info = await (widget.loadAppInfo ?? fetchAppInfo)();
    // 식단과 안내 정보는 독립적으로 갱신된다. info.json이 늦게 저장돼도
    // 위젯이 오류 화면에 머물지 않도록 각 cache 성공 뒤 따로 다시 그린다.
    unawaited(_refreshHomeWidgetsAfterInfoCache());
    return info;
  }

  /// 네트워크 응답이 실패하면 캐시로 그린 화면을 그대로 둔다.
  Future<void> _replaceAppInfoWithFresh(
    Future<AppInfo> fresh,
    Future<bool> freshFailed,
  ) async {
    if (await freshFailed) return;
    if (!mounted) return;
    // 화살표 본문은 대입 결과인 Future를 돌려주어 setState assert에 걸린다.
    setState(() {
      appInfo = fresh;
    });
  }

  Future<void> _refreshHomeWidgetsAfterInfoCache() async {
    try {
      await (widget.refreshHomeWidgets ?? updateHomeWidgets)();
    } catch (e) {
      assert(() {
        debugPrint('[BapU] widget refresh after info cache failed: $e');
        return true;
      }());
    }
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
                mealNotificationPlatform !=
                    MealNotificationPlatform.unsupported &&
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
        )?.reconcileMealNotificationsAfterForegroundRefresh();
      }
      return meal;
    });
    _mealRefreshQueue = queuedRefresh.then<void>((_) {}, onError: (_, _) {});
    return queuedRefresh;
  }

  void _checkAnnouncement() {
    checkForNewAnnouncement(loadInfo: () => _freshAppInfo)
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
