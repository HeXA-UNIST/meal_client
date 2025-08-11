import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../model.dart';
import '../meal.dart';
import '../data.dart';
import '../i18n.dart';
import '../string.dart' as string;

class DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const DrawerItem({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      contentPadding: EdgeInsets.only(left: 40),
      onTap: onTap,
    );
  }
}

class _HomePageDrawer extends StatelessWidget {
  const _HomePageDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final language = Provider.of<BapUModel>(context).language;

    return Drawer(
      backgroundColor: brightness == Brightness.light
          ? Theme.of(context).colorScheme.primaryContainer
          : Color(0xFFF0F0F0),

      child: ListView(
        padding: EdgeInsets.all(0),
        children: [
          Container(
            height: 160,
            alignment: Alignment.bottomLeft,
            margin: EdgeInsets.only(bottom: 50, left: 40),
            child: SvgPicture.asset('assets/imgs/bapu_logo.svg', height: 36),
          ),
          DrawerItem(
            icon: Icons.notifications_active,
            title: string.notification.getLocalizedString(language),
            onTap: () {},
          ),
          DrawerItem(
            icon: Icons.info,
            title: string.operationinfo.getLocalizedString(language),
            onTap: () {},
          ),
          DrawerItem(
            icon: Icons.help_outline_outlined,
            title: string.contactdeveloper.getLocalizedString(language),
            onTap: () {},
          ),
          DrawerItem(
            icon: Icons.language,
            title: "언어 / Language",
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _MealOfDaySwitchButton extends StatelessWidget {
  const _MealOfDaySwitchButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  final void Function()? onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      label: SizedBox(
        width: 40,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
      icon: Icon(icon),
      style: TextButton.styleFrom(
        iconColor: colorScheme.onPrimaryContainer,
        backgroundColor: colorScheme.primaryContainer,
        overlayColor: colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _DayOfWeekTabBar extends StatelessWidget implements PreferredSizeWidget {
  _DayOfWeekTabBar({
    super.key,
    required this.tabController,
    required this.language,
  });

  final TabController tabController;
  final Language language;

  final _preferredSize = Size.fromHeight(46.0);

  @override
  Size get preferredSize => _preferredSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final unselectedLabelColor = Color(0xFF939393);

    return PreferredSize(
      preferredSize: _preferredSize,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(128.0),
        ),
        margin: EdgeInsets.symmetric(horizontal: 8.0),
        padding: EdgeInsets.all(4.0),
        child: TabBar(
          tabs: [
            Tab(text: string.mon.getLocalizedString(language), height: 36),
            Tab(text: string.tue.getLocalizedString(language), height: 36),
            Tab(text: string.wed.getLocalizedString(language), height: 36),
            Tab(text: string.thu.getLocalizedString(language), height: 36),
            Tab(text: string.fri.getLocalizedString(language), height: 36),
            Tab(text: string.sat.getLocalizedString(language), height: 36),
            Tab(text: string.sun.getLocalizedString(language), height: 36),
          ],
          labelColor: colorScheme.onPrimaryContainer,
          unselectedLabelColor: unselectedLabelColor,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(128),
          ),
          labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          labelPadding: EdgeInsets.zero,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => Colors.transparent,
          ),
          splashFactory: NoSplash.splashFactory,
          dividerHeight: 0,
          controller: tabController,
        ),
      ),
    );
  }
}

class _WeekMealTabBarView extends StatelessWidget {
  const _WeekMealTabBarView({
    super.key,
    required this.weekMeal,
    required this.tabController,
    required this.pageController,
    required this.onPageChanged,
  });

  final WeekMeal weekMeal;
  final TabController tabController;
  final PageController pageController;
  final void Function(int) onPageChanged;

  @override
  Widget build(BuildContext context) {
    final mealOfDays = List<Widget>.empty(growable: true);
    for (var mealOfDay in MealOfDay.values) {
      final days = List<Widget>.empty(growable: true);
      for (var day in DayOfWeek.values) {
        final meal = List<Widget>.empty(growable: true);
        final nowMealOfDay = weekMeal
            .fromDayOfWeek(day)
            .fromMealOfDay(mealOfDay);

        // TODO - replace Text widgets
        for (var dormitory in nowMealOfDay.dormitory) {
          meal.add(Text("Dormitory: ${dormitory.menu}"));
        }
        for (var student in nowMealOfDay.student) {
          meal.add(Text("Student: ${student.menu}"));
        }
        for (var faculty in nowMealOfDay.faculty) {
          meal.add(Text("Faculty: ${faculty.menu}"));
        }
        days.add(Column(children: meal));
      }
      mealOfDays.add(TabBarView(controller: tabController, children: days));
    }

    return Scrollbar(
      child: PageView(
        controller: pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: onPageChanged,
        children: mealOfDays,
      ),
    );
  }
}

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
  late final PageController _mealOfDayPageController;

  late final Future<WeekMeal> cachedMeal;
  late final Future<WeekMeal> downloadedMeal;

  @override
  void initState() {
    final DateTime now;
    {
      final localNow = DateTime.now();
      now = localNow.toUtc().add(Duration(hours: 9));
    }

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
      dayOfWeek: dayOfWeekFromISO8601(now.weekday),
    );

    _mondayOfWeek = now.subtract(Duration(days: now.weekday - 1));

    _tabController = TabController(length: 7, vsync: this);
    _tabController.index = iso8601FromDayOfWeek(_model.dayOfWeek) - 1;
    _tabController.addListener(
      () => setState(() {
        _model.dayOfWeek = dayOfWeekFromISO8601(_tabController.index + 1);
      }),
    );

    _mealOfDayPageController = PageController(
      initialPage: _model.mealOfDay.index,
    );

    cachedMeal = getCachedMealData();
    downloadedMeal = cachedMeal.then(
      (cache) => fetchAndCacheMealData(),
      onError: (e) => fetchAndCacheMealData(),
    );

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

        final theDay = _mondayOfWeek.add(
          Duration(days: iso8601FromDayOfWeek(_model.dayOfWeek) - 1),
        );

        final dayOfWeekTabBar = _DayOfWeekTabBar(
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
          drawer: const _HomePageDrawer(),
          appBar: AppBar(
            titleSpacing: 0,
            title: MediaQuery.of(context).size.width >= 840
                ? Row(
                    children: [
                      const SizedBox(width: 4),
                      Text(
                        string.getLocalizedDate(
                          theDay.month,
                          theDay.day,
                          bapu.language,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  )
                : Text(
                    string.getLocalizedDate(
                      theDay.month,
                      theDay.day,
                      bapu.language,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
            actions: [
              _MealOfDaySwitchButton(
                onPressed: () => setState(() {
                  _model.mealOfDay = nextMealOfDay(_model.mealOfDay);
                  try {
                    _mealOfDayPageController.animateToPage(
                      _model.mealOfDay.index,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.ease,
                    );
                  } catch (e) {
                    // ignore
                  }
                }),
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
                  return _WeekMealTabBarView(
                    weekMeal: downloadSnapshot.hasData
                        ? downloadSnapshot.data!
                        : cacheSnapshot.data!,
                    tabController: _tabController,
                    pageController: _mealOfDayPageController,
                    onPageChanged: (page) => setState(
                      () => _model.mealOfDay = MealOfDay.values[page],
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
}
