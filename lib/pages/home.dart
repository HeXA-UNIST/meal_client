import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model.dart';
import '../meal.dart';
import '../i18n.dart';
import '../string.dart' as string;

class _HomePageDrawer extends StatelessWidget {
  const _HomePageDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      shape: Border(),
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
        width: 64,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
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

  final _preferredSize = Size.fromHeight(48.0);

  @override
  Size get preferredSize => _preferredSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final unselectedLabelColor = Color.fromARGB(0xff, 0x80, 0x80, 0x80);

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
          labelStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late int _month;
  late int _day;
  late MealOfDay _mealOfDay;

  late TabController _tabController;

  @override
  void initState() {
    _month = 6;
    _day = 27;
    _mealOfDay = MealOfDay.lunch;

    _tabController = TabController(length: 7, vsync: this);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BapUModel>(
      builder: (context, bapu, child) {
        final String dayOfMealLabel;
        final IconData dayOfMealIcon;
        switch (_mealOfDay) {
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

        return Scaffold(
          drawer: const _HomePageDrawer(),
          appBar: AppBar(
            title: Text(
              string.getLocalizedDate(_month, _day, bapu.language),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              _MealOfDaySwitchButton(
                onPressed: () => setState(() {
                  _mealOfDay = nextMealOfDay(_mealOfDay);
                }),
                label: dayOfMealLabel,
                icon: dayOfMealIcon,
              ),
            ],
            actionsPadding: EdgeInsets.only(right: 8),
            bottom: _DayOfWeekTabBar(
              tabController: _tabController,
              language: bapu.language,
            ),
          ),
          body: child,
        );
      },
    );
  }
}
