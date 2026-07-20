import 'package:flutter/material.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'home_app_bar.dart';
import 'model.dart';
import 'nested_page_scroll.dart';
import 'week_meal_view.dart';

/// [HomePage]와 다음 주 미리보기 화면이 공유하는 화면 뼈대.
/// AppBar(요일 탭 + 끼니 전환 버튼), 데이터 로딩 FutureBuilder 체인,
/// TabController/PageController 생명주기를 소유한다.
class WeekMenuScaffold extends StatefulWidget {
  const WeekMenuScaffold({
    super.key,
    required this.mondayOfWeek,
    required this.initialDayOfWeek,
    required this.initialMealOfDay,
    required this.mealFuture,
    this.cachedMealFuture,
    required this.appInfo,
    this.bannerText,
    this.drawer,
  });

  final DateTime mondayOfWeek;
  final DayOfWeek initialDayOfWeek;
  final MealOfDay initialMealOfDay;
  final Future<WeekMeal> mealFuture;
  final Future<WeekMeal>? cachedMealFuture;
  final Future<AppInfo> appInfo;
  final String? bannerText;
  final Widget? drawer;

  @override
  State<WeekMenuScaffold> createState() => _WeekMenuScaffoldState();
}

class _WeekMenuScaffoldState extends State<WeekMenuScaffold>
    with SingleTickerProviderStateMixin {
  late final HomePageModel _model;
  late final TabController _tabController;
  late final NestedPageScrollControllerGroup _mealOfDayPageControllerGroup;

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
    _model = HomePageModel(
      mealOfDay: widget.initialMealOfDay,
      dayOfWeek: widget.initialDayOfWeek,
    );
    _mealOfDayNotifier = ValueNotifier(_model.mealOfDay);

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final dayOfWeekTabBar = DayOfWeekTabBar(tabController: _tabController);
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

    Widget body = _buildBody(l10n);
    final bannerText = widget.bannerText;
    if (bannerText != null) {
      body = Column(
        children: [_PreviewBanner(text: bannerText), Expanded(child: body)],
      );
    }

    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: AnimatedDateTitle(
          tabController: _tabController,
          mondayOfWeek: widget.mondayOfWeek,
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
                      curve: Curves.easeOutCubic,
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
      body: body,
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final cachedMealFuture = widget.cachedMealFuture;

    if (cachedMealFuture == null) {
      return FutureBuilder<WeekMeal>(
        future: widget.mealFuture,
        builder: (context, snapshot) {
          final theme = Theme.of(context);
          if (snapshot.hasData) {
            return _buildTabBarView(snapshot.data!);
          } else if (snapshot.hasError) {
            return Center(
              child: Text(l10n.cannotLoadMeal, style: theme.textTheme.titleMedium),
            );
          } else {
            return Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primaryContainer,
              ),
            );
          }
        },
      );
    }

    return FutureBuilder<WeekMeal>(
      future: cachedMealFuture,
      builder: (context, cacheSnapshot) {
        final theme = Theme.of(context);

        if (cacheSnapshot.hasData || cacheSnapshot.hasError) {
          return FutureBuilder<WeekMeal>(
            future: widget.mealFuture,
            builder: (context, downloadSnapshot) {
              if (downloadSnapshot.hasData || cacheSnapshot.hasData) {
                return _buildTabBarView(
                  downloadSnapshot.hasData
                      ? downloadSnapshot.data!
                      : cacheSnapshot.data!,
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
                    l10n.cannotLoadMeal,
                    style: theme.textTheme.titleMedium,
                  ),
                );
              }
            },
          );
        } else {
          return Center(
            child: CircularProgressIndicator(
              color: theme.colorScheme.primaryContainer,
            ),
          );
        }
      },
    );
  }

  Widget _buildTabBarView(WeekMeal weekMeal) {
    return WeekMealTabBarView(
      pageCount: MealOfDay.values.length,
      weekMeal: weekMeal,
      tabController: _tabController,
      pageControllerGroup: _mealOfDayPageControllerGroup,
      appInfo: widget.appInfo,
      mondayOfWeek: widget.mondayOfWeek,
      onPageChanged: (page) {
        // 버튼으로 시작한 전환 중에는 중간 페이지(예: 점심)를
        // 상단 버튼 상태에 반영하지 않는다.
        if (_isMealOfDayButtonTransition) {
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mealOfDayPageControllerGroup.dispose();
    _mealOfDayNotifier.dispose();
    super.dispose();
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
