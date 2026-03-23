import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api_v2.dart';
import '../../data.dart';
import '../../meal.dart';
import '../../model.dart';
import '../../string.dart' as string;
import '../home_drawer.dart';
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

  // 버튼으로 시작한 식사 전환 동안에는 상단 버튼 상태를 유지하고,
  // 중간 onPageChanged가 버튼 상태를 다시 덮어쓰지 않게 한다.
  bool _isMealOfDayButtonTransition = false;

  @override
  void initState() {
    final DateTime now;
    {
      final localNow = DateTime.now();
      now = localNow.toUtc().add(Duration(hours: 9));
    }

    // TODO: 나중에 API에서 운영 시간 정보를 받아와야함
    final MealOfDay mealOfDay;
    if (now.hour < 9 || (now.hour == 9 && now.minute <= 20)) {
      mealOfDay = MealOfDay.breakfast;
    } else if (now.hour < 13 || (now.hour == 13 && now.minute <= 30)) {
      mealOfDay = MealOfDay.lunch;
    } else {
      mealOfDay = MealOfDay.dinner;
    }

    _model = HomePageModel(
      mealOfDay: mealOfDay,
      dayOfWeek: DayOfWeek.values[now.weekday - 1],
    );

    _mondayOfWeek = now.subtract(Duration(days: now.weekday - 1));

    _tabController = TabController(
      length: DayOfWeek.values.length,
      vsync: this,
    );
    _tabController.index = _model.dayOfWeek.index;
    _tabController.addListener(
      () {
        final nextDayOfWeek = DayOfWeek.values[_tabController.index];
        if (_model.dayOfWeek == nextDayOfWeek) {
          return;
        }

        setState(() {
          _model.dayOfWeek = nextDayOfWeek;
        });
      },
    );

    _mealOfDayPageControllerGroup = NestedPageScrollControllerGroup(
      count: DayOfWeek.values.length,
      pageCount: MealOfDay.values.length,
      initialPage: _model.mealOfDay.index,
    );

    cachedMeal = getCachedMealData();
    downloadedMeal = cachedMeal.then(
      (cache) => fetchAndCacheMealData(),
      onError: (e) => fetchAndCacheMealData(),
    ).catchError((e) {
      assert(() {
        debugPrint('[BapU] meal fetch failed: $e');
        return true;
      }());
      throw e;
    });

    fetchRawAnnouncement().then((rawAnnouncement) async {
      const key = "announceTime";
      try {
        final announcement = parseRawAnnouncement(rawAnnouncement);
        final sharedPreferences = await SharedPreferences.getInstance();
        if (!mounted) return;
        final prevAnnouncement = sharedPreferences.getString(key);
        if (announcement != prevAnnouncement) {
          sharedPreferences.setString(key, announcement);
          SchedulerBinding.instance.addPostFrameCallback((duration) {
            if (!mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) {
                return Consumer<BapUModel>(
                  builder: (context, bapu, child) => HomeAnnouncementDialog(
                    close: string.close.getLocalizedString(bapu.language),
                    title: string.announcement.getLocalizedString(
                      bapu.language,
                    ),
                    content: announcement,
                  ),
                );
              },
            );
          });
        }
      } catch (e) {
        assert(() {
          debugPrint('[BapU] announcement processing failed: $e');
          return true;
        }());
      }
    // 네트워크 오류·타임아웃 등 fetchRawAnnouncement() 자체의 예외는
    // then() 콜백 안 try/catch로 잡히지 않으므로 별도로 처리한다.
    // 공지사항 로드 실패는 조용히 무시한다.
    }).catchError((e) {
      assert(() {
        debugPrint('[BapU] announcement fetch failed: $e');
        return true;
      }());
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BapUModel>(
      builder: (context, bapu, child) {
        final String dayOfMealLabel;
        final IconData dayOfMealIcon;
        switch (_model.mealOfDay) {
          case MealOfDay.breakfast:
            dayOfMealLabel = string.breakfast.getLocalizedString(bapu.language);
            dayOfMealIcon = Icons.sunny;
          case MealOfDay.lunch:
            dayOfMealLabel = string.lunch.getLocalizedString(bapu.language);
            dayOfMealIcon = Icons.restaurant;
          case MealOfDay.dinner:
            dayOfMealLabel = string.dinner.getLocalizedString(bapu.language);
            dayOfMealIcon = Icons.nightlight;
        }

        final dayOfWeekTabBar = DayOfWeekTabBar(
          tabController: _tabController,
          language: bapu.language,
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
              language: bapu.language,
            ),
            actions: [
              MealOfDaySwitchButton(
                onPressed: () async {
                  final nextMeal = nextMealOfDay(_model.mealOfDay);

                  setState(() {
                    // 버튼은 누르자마자 다음 식사 상태로 바꿔 즉각적인 반응을 준다.
                    _model.mealOfDay = nextMeal;
                    _isMealOfDayButtonTransition = true;
                  });

                  try {
                    await _mealOfDayPageControllerGroup.animateToPage(
                      nextMeal.index,
                      duration: Duration(milliseconds: 300),
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
                label: dayOfMealLabel,
                icon: dayOfMealIcon,
              ),
            ],
            actionsPadding: EdgeInsets.only(right: 8),
            backgroundColor: colorScheme.surface,
            scrolledUnderElevation: 0,
            bottom: bottom,
            flexibleSpace: flexibleSpace,
          ),
          body: child,
        );
      },
      child: FutureBuilder(
        future: cachedMeal,
        builder: (context, cacheSnapshot) {
          final theme = Theme.of(context);

          if (cacheSnapshot.hasData || cacheSnapshot.hasError) {
            return FutureBuilder(
              future: downloadedMeal,
              builder: (context, downloadSnapshot) {
                if (downloadSnapshot.hasData || cacheSnapshot.hasData) {
                  return Consumer<BapUModel>(
                    builder: (context, bapu, child) => WeekMealTabBarView(
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
                        if (_model.mealOfDay == nextMealOfDay) {
                          return;
                        }

                        // 수동 스와이프 전환은 기존처럼 즉시 버튼 상태에 반영한다.
                        setState(() {
                          _model.mealOfDay = nextMealOfDay;
                        });
                      },
                      language: bapu.language,
                    ),
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
                    child: Consumer<BapUModel>(
                      builder: (context, bapu, child) => Text(
                        string.cannotLoadMeal.getLocalizedString(bapu.language),
                        style: theme.textTheme.titleMedium,
                      ),
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

  @override
  void dispose() {
    _tabController.dispose();
    _mealOfDayPageControllerGroup.dispose();
    super.dispose();
  }
}
