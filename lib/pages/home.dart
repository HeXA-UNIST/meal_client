import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../model.dart';
import '../meal.dart';
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _month;
  late int _day;
  late MealOfDay _mealOfDay;

  @override
  void initState() {
    _month = 6;
    _day = 27;
    _mealOfDay = MealOfDay.lunch;

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
          ),
          body: child,
        );
      },
    );
  }
}
