import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'week_menu_scaffold.dart';

typedef DatedWeekMealLoader = Future<WeekMeal> Function(String weekStart);

class NextWeekPreviewPage extends StatefulWidget {
  const NextWeekPreviewPage({
    super.key,
    required this.nextWeekStartFuture,
    required this.appInfo,
    this.refreshNextWeekStart,
    this.loadDatedWeek,
    this.onNextWeekMealRefreshed,
  });

  final Future<String?> nextWeekStartFuture;
  final Future<AppInfo> appInfo;
  final Future<String?> Function()? refreshNextWeekStart;
  final DatedWeekMealLoader? loadDatedWeek;
  final VoidCallback? onNextWeekMealRefreshed;

  @override
  State<NextWeekPreviewPage> createState() => _NextWeekPreviewPageState();
}

class _NextWeekPreviewPageState extends State<NextWeekPreviewPage> {
  late final Future<String?> _nextWeekStartFuture;

  @override
  void initState() {
    super.initState();
    _nextWeekStartFuture = widget.nextWeekStartFuture.then((nextWeekStart) {
      if (nextWeekStart != null) return nextWeekStart;
      return (widget.refreshNextWeekStart ?? _refreshNextWeekStart)();
    });
  }

  Future<String?> _refreshNextWeekStart() async {
    final response = await fetchAndCacheMealData(prefetchNextWeek: false);
    return response.weekMeta.nextWeekStart;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<String?>(
      future: _nextWeekStartFuture,
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
          appInfo: widget.appInfo,
          loadDatedWeek: widget.loadDatedWeek ?? fetchAndCacheMealDataForWeek,
          onMealRefreshed: widget.onNextWeekMealRefreshed,
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
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Center(child: child),
    );
  }
}

class _NextWeekMenu extends StatefulWidget {
  const _NextWeekMenu({
    required this.nextWeekStart,
    required this.appInfo,
    required this.loadDatedWeek,
    this.onMealRefreshed,
  });

  final String nextWeekStart;
  final Future<AppInfo> appInfo;
  final DatedWeekMealLoader loadDatedWeek;
  final VoidCallback? onMealRefreshed;

  @override
  State<_NextWeekMenu> createState() => _NextWeekMenuState();
}

class _NextWeekMenuState extends State<_NextWeekMenu> {
  late final DateTime _mondayOfWeek;
  late final Future<WeekMeal> _mealFuture;

  @override
  void initState() {
    super.initState();
    _mondayOfWeek = parseWeekStartDate(widget.nextWeekStart);
    _mealFuture = widget.loadDatedWeek(widget.nextWeekStart).then((meal) {
      final callback = widget.onMealRefreshed;
      if (callback != null) {
        callback();
      } else if (mounted) {
        Provider.of<AppSettings?>(
          context,
          listen: false,
        )?.reconcileMealNotificationsAfterForegroundRefresh();
      }
      return meal;
    });
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
          titleFontWeight: FontWeight.w600,
        );
      },
    );
  }
}
