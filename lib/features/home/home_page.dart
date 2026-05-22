import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:meal_client/features/announcement/announcement_service.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/widget/widget_service.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'home_drawer.dart';
import 'model.dart';
import 'home_app_bar.dart';
import 'nested_page_scroll.dart';
import 'week_meal_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final HomePageModel _model;
  late final DateTime _mondayOfWeek;
  late final TabController _tabController;
  late final NestedPageScrollControllerGroup _mealOfDayPageControllerGroup;

  late final Future<WeekMeal> cachedMeal;
  late final Future<WeekMeal> downloadedMeal;

  // 끼니 상태는 ValueNotifier로 관리한다.
  // MealOfDaySwitchButton만 이 값을 구독하므로, 끼니 전환 시
  // Scaffold 전체가 아닌 버튼 하나만 rebuild된다.
  late final ValueNotifier<MealOfDay> _mealOfDayNotifier;

  // 버튼으로 시작한 식사 전환 동안에는 상단 버튼 상태를 유지하고,
  // 중간 onPageChanged가 버튼 상태를 다시 덮어쓰지 않게 한다.
  bool _isMealOfDayButtonTransition = false;

  @override
  void initState() {
    super.initState();
    _initializeModelAndDate();
    _initializeDataLoading();
    _initializeControllers();
    _checkAnnouncement();
  }

  void _initializeModelAndDate() {
    final kstNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    _model = HomePageModel(
      mealOfDay: MealTimeConfig.determineMealOfDay(kstNow),
      dayOfWeek: DayOfWeek.values[kstNow.weekday - 1],
    );
    _mondayOfWeek = kstNow.subtract(Duration(days: kstNow.weekday - 1));
    _mealOfDayNotifier = ValueNotifier(_model.mealOfDay);
  }

  void _initializeDataLoading() {
    cachedMeal = getCachedMealData();
    downloadedMeal = cachedMeal.then(
      (cache) => fetchAndCacheMealData(),
      onError: (e) => fetchAndCacheMealData(),
    ).then((meal) {
      updateHomeWidgets();
      return meal;
    }).catchError((e) {
      assert(() {
        debugPrint('[BapU] meal fetch failed: $e');
        return true;
      }());
      throw e;
    });
  }

  void _initializeControllers() {
    _tabController = TabController(
      length: DayOfWeek.values.length,
      vsync: this,
      initialIndex: _model.dayOfWeek.index,
    );
    _tabController.addListener(_onTabChanged);

    _mealOfDayPageControllerGroup = NestedPageScrollControllerGroup(
      count: DayOfWeek.values.length,
      pageCount: MealOfDay.values.length,
      initialPage: _model.mealOfDay.index,
    );
  }

  void _onTabChanged() {
    final nextDayOfWeek = DayOfWeek.values[_tabController.index];
    if (_model.dayOfWeek == nextDayOfWeek) {
      return;
    }
    // setState 없이 직접 대입한다: _model.dayOfWeek는 build()의 위젯 트리에서
    // 직접 사용되지 않으므로(animateToPage의 activeIndex는 onPressed 콜백에서만
    // 읽힘) rebuild를 발생시킬 이유가 없다.
    _model.dayOfWeek = nextDayOfWeek;
  }

  void _checkAnnouncement() {
    checkForNewAnnouncement().then((announcement) {
      if (announcement != null && mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showAnnouncementDialog(announcement);
        });
      }
    }).catchError((e) {
      assert(() {
        debugPrint('[BapU] announcement fetch failed: $e');
        return true;
      }());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final dayOfWeekTabBar = DayOfWeekTabBar(
      tabController: _tabController,
    );
    final PreferredSizeWidget? bottom;
    final Widget? flexibleSpace;
    if (MediaQuery.of(context).size.width >= 840) {
      flexibleSpace = SafeArea(
        child: Center(child: SizedBox(width: 420, child: dayOfWeekTabBar)),
      );
      bottom = null;
    } else {
      bottom = dayOfWeekTabBar;
      flexibleSpace = null;
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: const HomePageDrawer(),
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: AnimatedDateTitle(
          tabController: _tabController,
          mondayOfWeek: _mondayOfWeek,
        ),
        actions: [
          ValueListenableBuilder<MealOfDay>(
            valueListenable: _mealOfDayNotifier,
            builder: (context, mealOfDay, _) {
              final (label, icon) = switch (mealOfDay) {
                MealOfDay.breakfast => (l10n.breakfast, Icons.sunny),
                MealOfDay.lunch => (l10n.lunch, Icons.restaurant),
                MealOfDay.dinner => (l10n.dinner, Icons.nightlight),
              };
              return MealOfDaySwitchButton(
                onPressed: () async {
                  // _mealOfDayNotifier.value를 직접 읽어 연속 탭 시에도
                  // 클로저에 캡처된 mealOfDay가 아닌 최신 상태를 사용한다.
                  final nextMeal = _mealOfDayNotifier.value.next;

                  // 버튼은 누르자마자 다음 식사 상태로 바꿔 즉각적인 반응을 준다.
                  _mealOfDayNotifier.value = nextMeal;
                  _isMealOfDayButtonTransition = true;

                  try {
                    await _mealOfDayPageControllerGroup.animateToPage(
                      nextMeal.index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.ease,
                      // 현재 선택된 요일 탭만 애니메이션 처리
                      activeIndex: _model.dayOfWeek.index,
                    );
                  } finally {
                    // _isMealOfDayButtonTransition은 build()가 아닌
                    // onPageChanged 콜백에서만 읽힌다. 콜백은 this를 캡처하여
                    // 호출 시점의 필드 값을 직접 읽으므로, setState 없이
                    // 해제해도 렌더링에 영향이 없다.
                    _isMealOfDayButtonTransition = false;
                  }
                },
                label: label,
                icon: icon,
              );
            },
          ),
        ],
        actionsPadding: const EdgeInsets.only(right: 8),
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
        bottom: bottom,
        flexibleSpace: flexibleSpace,
      ),
      body: FutureBuilder(
        future: cachedMeal,
        builder: (context, cacheSnapshot) {
          final theme = Theme.of(context);

          if (cacheSnapshot.hasData || cacheSnapshot.hasError) {
            return FutureBuilder(
              future: downloadedMeal,
              builder: (context, downloadSnapshot) {
                if (downloadSnapshot.hasData || cacheSnapshot.hasData) {
                  return WeekMealTabBarView(
                    pageCount: MealOfDay.values.length,
                    weekMeal: downloadSnapshot.hasData
                        ? downloadSnapshot.data!
                        : cacheSnapshot.data!,
                    tabController: _tabController,
                    pageControllerGroup: _mealOfDayPageControllerGroup,
                    onPageChanged: (page) {
                      if (_isMealOfDayButtonTransition) {
                        // 버튼으로 시작한 전환 중에는 중간 페이지(예: 점심)를
                        // 상단 버튼 상태에 반영하지 않는다.
                        return;
                      }

                      final nextMealOfDay = MealOfDay.values[page];
                      if (_mealOfDayNotifier.value == nextMealOfDay) {
                        return;
                      }

                      // 수동 스와이프 전환은 기존처럼 즉시 버튼 상태에 반영한다.
                      // ValueNotifier 갱신으로 MealOfDaySwitchButton만 rebuild된다.
                      _mealOfDayNotifier.value = nextMealOfDay;
                    },
                  );
                } else if (!cacheSnapshot.hasError ||
                    !downloadSnapshot.hasError) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primaryContainer,
                    ),
                  );
                } else {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context)!.cannotLoadMeal,
                      style: theme.textTheme.titleMedium,
                    ),
                  );
                }
              },
            );
          } else {
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
            );
          }
        },
      ),
    );
  }

  void _showAnnouncementDialog(String announcement) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return HomeAnnouncementDialog(
          close: l10n.close,
          title: l10n.announcement,
          content: announcement,
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mealOfDayPageControllerGroup.dispose();
    _mealOfDayNotifier.dispose();
    super.dispose();
  }
}
