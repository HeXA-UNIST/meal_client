import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/info/announcement_state.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_data_source.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/notification/notification_platform.dart';
import 'package:meal_client/features/widget/widget_service.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/features/settings/bapu_settings.dart';

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
  DateTime? _infoCacheReadyAt;
  Future<void> _mealRefreshQueue = Future.value();
  Timer? _displayTimer;
  AppInfo? _displayInfo;
  bool _displayActive =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 다운로드와 무관하게 기존 캐시로 위젯 표시와 다음 갱신 예약을 복구한다.
    unawaited(_refreshHomeWidgetsFromCache());
    _initializeModelAndDate();
    _initializeDataLoading();
    _freshAppInfo = _fetchFreshAppInfo();
    appInfo = _loadAppInfo(_freshAppInfo);
    // 운영시간을 아직 못 읽어도 자정과 주차 경계는 갱신한다.
    _scheduleDisplayRefresh();
    // 화면의 FutureBuilder가 붙기 전에 실패하면 listener가 없어 unhandled async
    // error가 된다. 오류 표시는 그대로 FutureBuilder가 맡고, 여기서는 관찰만 한다.
    unawaited(appInfo.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    unawaited(_checkStartupDialogs());
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
    if (cached == null) {
      final info = await fresh;
      if (mounted) {
        _displayInfo = info;
        _scheduleDisplayRefresh();
      }
      return info;
    }
    if (mounted) {
      _displayInfo = cached;
      _scheduleDisplayRefresh();
    }
    unawaited(_replaceAppInfoWithFresh(fresh, freshFailed));
    return cached;
  }

  Future<AppInfo> _fetchFreshAppInfo() async {
    final injectedLoader = widget.loadAppInfo;
    final result = injectedLoader == null
        ? await fetchAppInfoWithStatus()
        : (info: await injectedLoader(), cacheReady: false);
    // 식단과 안내 정보는 독립적으로 갱신된다. info.json이 늦게 저장돼도
    // 위젯이 오류 화면에 머물지 않도록 각 cache 성공 뒤 따로 다시 그린다.
    try {
      await (widget.refreshHomeWidgets ??
          () => refreshWidgets(throwOnFailure: true))();
      if (result.cacheReady) _infoCacheReadyAt = _now();
    } catch (error) {
      debugPrint('[BapU] widget refresh after info failed: $error');
    }
    return result.info;
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
    _displayInfo = await fresh;
    if (mounted) _scheduleDisplayRefresh();
  }

  Future<void> _refreshHomeWidgetsFromCache() async {
    try {
      await (widget.refreshHomeWidgets ?? updateHomeWidgets)();
    } catch (e) {
      assert(() {
        debugPrint('[BapU] widget refresh from cache failed: $e');
        return true;
      }());
    }
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  /// 조작이 없어도 다음 운영시간 경계나 KST 자정에 표시를 다시 계산한다.
  void _scheduleDisplayRefresh() {
    _displayTimer?.cancel();
    if (!_displayActive || !mounted) return;
    final now = MealTimeConfig.toKst(_now());
    final today = DateTime.utc(now.year, now.month, now.day);
    var next = today.add(const Duration(days: 1));
    final period = _displayInfo?.operatingHours.forDate(now);
    if (period != null) {
      for (final cafeteria in period.cafeterias) {
        for (final range in period.timesFor(cafeteria)) {
          for (final (time, extraMinute) in [
            (range.start, 0),
            (range.end, 1),
          ]) {
            final parts = time.split(':').map(int.parse).toList();
            // contains()가 종료 분 전체를 포함하므로 그 다음 분에 상태를 바꾼다.
            final boundary = today.add(
              Duration(hours: parts[0], minutes: parts[1] + extraMinute),
            );
            if (boundary.isAfter(now) && boundary.isBefore(next)) {
              next = boundary;
            }
          }
        }
      }
    }
    _displayTimer = Timer(next.difference(now), _refreshDisplay);
  }

  void _refreshDisplay() {
    if (!mounted || !_displayActive) return;
    final now = _now();
    setState(() {
      if (_weekId != MealTimeConfig.kstWeekId(now)) {
        _initializeModelAndDate(now);
        _initializeDataLoading();
      }
    });
    _scheduleDisplayRefresh();
  }

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
    _displayActive = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _displayTimer?.cancel();
      return;
    }

    // 같은 주의 복귀나 오프라인 상태에서도 위젯 갱신을 다시 요청한다.
    unawaited(_refreshHomeWidgetsFromCache());
    _refreshDisplay();
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
    final refreshStartedAt = _now();
    Future<bool> cacheReady = Future.value(false);
    final refreshMeal =
        widget.refreshMeal ??
        () async {
          final now = _now();
          final result = await fetchAndCacheCanonicalMealDataWithStatus(
            now: now,
            waitForNextWeekPrefetch:
                mealNotificationPlatform !=
                    MealNotificationPlatform.unsupported &&
                MealTimeConfig.toKst(now).weekday == DateTime.sunday,
          );
          cacheReady = result.cacheReady;
          return (weekMeal: result.weekMeal, weekMeta: result.weekMeta);
        };
    final queuedRefresh = _mealRefreshQueue.then((_) async {
      try {
        await cachedMealRecord;
      } catch (_) {
        // 캐시 실패는 기존 동작처럼 네트워크 갱신으로 복구한다.
      }
      final meal = await refreshMeal();
      var widgetReady = true;
      try {
        await (widget.refreshHomeWidgets ??
            () => refreshWidgets(throwOnFailure: true))();
      } catch (error) {
        widgetReady = false;
        debugPrint('[BapU] widget refresh after meal failed: $error');
      }
      if (mounted) {
        final settings = Provider.of<BapuSettings?>(context, listen: false);
        // 선반입이 완료된 스냅샷으로 알림을 맞추되 화면 표시는 기다리지 않는다.
        final notificationsReady = cacheReady.then(
          (_) =>
              settings?.reconcileMealNotificationsAfterForegroundRefresh() ??
              Future.value(false),
        );
        unawaited(
          _postponeBackgroundRefreshAfterSuccess(
            refreshStartedAt,
            widgetReady ? cacheReady : Future.value(false),
            notificationsReady,
          ),
        );
      }
      return meal;
    });
    _mealRefreshQueue = queuedRefresh.then<void>((_) {}, onError: (_, _) {});
    return queuedRefresh;
  }

  Future<void> _postponeBackgroundRefreshAfterSuccess(
    DateTime refreshStartedAt,
    Future<bool> cacheReady,
    Future<bool> notificationsReady,
  ) async {
    try {
      final results = await Future.wait([
        cacheReady,
        notificationsReady,
        _freshAppInfo.then((_) {
          final readyAt = _infoCacheReadyAt;
          // 다른 주 재조회나 식단만 갱신한 복귀에 이전 info 성공을 재사용하지 않는다.
          return readyAt != null && !readyAt.isBefore(refreshStartedAt);
        }),
      ]);
      if (!mounted ||
          !results.every((ready) => ready) ||
          MealTimeConfig.kstWeekId(refreshStartedAt) !=
              MealTimeConfig.kstWeekId(_now())) {
        return;
      }
      await postponeMealBackgroundRefresh();
    } catch (error, stackTrace) {
      // 연기 실패로 화면 표시나 기존 주기 작업을 실패시키지 않는다.
      debugPrint('[BapU] background refresh postponement skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _checkStartupDialogs() async {
    // 권한 안내를 먼저 닫은 뒤 공지를 표시해 시작 팝업이 겹치지 않게 한다.
    try {
      await _showNotificationPermissionDialog();
    } catch (error, stackTrace) {
      debugPrint(
        '[BapU] startup notification authorization check failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    try {
      final announcement = await checkForNewAnnouncement(
        loadInfo: () => _freshAppInfo,
      );
      if (announcement == null) return;
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      await _showAnnouncementDialog(announcement);
    } catch (error) {
      assert(() {
        debugPrint('[BapU] announcement fetch failed: $error');
        return true;
      }());
    }
  }

  Future<void> _showNotificationPermissionDialog() async {
    final settings = context.read<BapuSettings?>();
    if (settings == null) return;
    final status = await settings.notificationPermissionReminderStatus();
    if (status == null) return;
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        !settings.notification.enabled) {
      return;
    }
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.mealNotificationPermissionTitle),
          content: Text(l10n.notificationPermissionRequired),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.later),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.openSystemAppSettings),
            ),
          ],
        );
      },
    );
    if (openSettings != true || !mounted || !settings.notification.enabled) {
      return;
    }
    try {
      await settings.restoreNotificationPermission();
    } catch (error, stackTrace) {
      debugPrint(
        '[BapU] startup notification permission request failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WeekMenuScaffold(
      key: ValueKey(_mondayOfWeek),
      mondayOfWeek: _mondayOfWeek,
      initialDayOfWeek: _initialDayOfWeek,
      today: DayOfWeek.values[MealTimeConfig.toKst(_now()).weekday - 1],
      currentKstDateTime: MealTimeConfig.toKst(_now()),
      initialMealOfDay: _initialMealOfDay,
      cachedMealFuture: cachedMeal,
      mealFuture: downloadedMeal,
      appInfo: appInfo,
      drawer: HomePageDrawer(infoFuture: appInfo, nextWeekStart: nextWeekStart),
    );
  }

  Future<void> _showAnnouncementDialog(AppAnnouncement announcement) async {
    final closed = showDialog<void>(
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
    await saveDisplayedAnnouncement(announcement);
    await closed;
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
