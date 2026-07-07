import 'package:flutter/material.dart';

import 'package:meal_client/core/network/http_client.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'week_menu_scaffold.dart';

class NextWeekPreviewPage extends StatelessWidget {
  const NextWeekPreviewPage({
    super.key,
    required this.nextWeekStartFuture,
    required this.appInfo,
    this.mealFetcher = fetchRawString,
  });

  final Future<String?> nextWeekStartFuture;
  final Future<AppInfo> appInfo;
  final RawMealFetcher mealFetcher;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<String?>(
      future: nextWeekStartFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _MessageScaffold(
            title: l10n.nextWeekPreview,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
        }

        final nextWeekStart = snapshot.data;
        if (nextWeekStart == null) {
          return _MessageScaffold(
            title: l10n.nextWeekPreview,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n.nextWeekNotReady,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }

        return _NextWeekMenu(
          nextWeekStart: nextWeekStart,
          appInfo: appInfo,
          mealFetcher: mealFetcher,
        );
      },
    );
  }
}

class _MessageScaffold extends StatelessWidget {
  const _MessageScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: child),
    );
  }
}

class _NextWeekMenu extends StatefulWidget {
  const _NextWeekMenu({
    required this.nextWeekStart,
    required this.appInfo,
    required this.mealFetcher,
  });

  final String nextWeekStart;
  final Future<AppInfo> appInfo;
  final RawMealFetcher mealFetcher;

  @override
  State<_NextWeekMenu> createState() => _NextWeekMenuState();
}

class _NextWeekMenuState extends State<_NextWeekMenu> {
  late final DateTime _mondayOfWeek;
  late final Future<WeekMeal> _mealFuture;

  @override
  void initState() {
    super.initState();
    _mondayOfWeek = DateTime.parse(widget.nextWeekStart);
    _mealFuture = fetchNextWeekMealData(
      widget.nextWeekStart,
      fetch: widget.mealFetcher,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<WeekMeal>(
      future: _mealFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageScaffold(
            title: l10n.nextWeekPreview,
            child: Text(
              l10n.cannotLoadMeal,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }
        if (!snapshot.hasData) {
          return _MessageScaffold(
            title: l10n.nextWeekPreview,
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
          );
        }

        return WeekMenuScaffold(
          mondayOfWeek: _mondayOfWeek,
          initialDayOfWeek: DayOfWeek.mon,
          initialMealOfDay: MealOfDay.breakfast,
          mealFuture: _mealFuture,
          appInfo: widget.appInfo,
          bannerText: l10n.previewingNextWeek,
        );
      },
    );
  }
}
