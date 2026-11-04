import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/meal/meal_data_source.dart';
import 'package:meal_client/features/settings/bapu_settings.dart';
import 'package:meal_client/l10n/app_localizations.dart';

import 'week_menu_scaffold.dart';

typedef DatedWeekMealLoader = Future<WeekMeal> Function(String weekStart);

Future<void> _showPreviewToast(BuildContext context, String message) async {
  final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  final isLight = Theme.of(context).brightness == Brightness.light;
  final backgroundColor = isLight
      ? const Color(0xFFF0F0F0)
      : const Color(0xFF454545);
  final textColor = isLight ? const Color(0xFF2E2E2E) : const Color(0xFFF5F5F5);
  await Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    timeInSecForIosWeb: isIos ? 2 : 1,
    // Android는 색상을 전달하지 않아 기본 네이티브 Toast를 유지한다.
    backgroundColor: isIos ? backgroundColor : null,
    textColor: isIos || kIsWeb ? textColor : null,
    webBgColor: isLight ? '#F0F0F0' : '#454545',
    webPosition: 'center',
  );
}

Future<void> openNextWeekPreview({
  required BuildContext context,
  required Future<String?> nextWeekStartFuture,
  required Future<AppInfo> appInfo,
}) async {
  String? nextWeekStart;
  try {
    nextWeekStart = await nextWeekStartFuture;
  } catch (error, stackTrace) {
    debugPrint('[BapU] next week metadata fetch failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (!context.mounted) return;
    await _showPreviewToast(
      context,
      AppLocalizations.of(context)!.cannotLoadMeal,
    );
    return;
  }
  if (!context.mounted) return;
  if (nextWeekStart == null) {
    await _showPreviewToast(
      context,
      AppLocalizations.of(context)!.nextWeekNotReady,
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NextWeekPreviewPage(
        nextWeekStartFuture: Future.value(nextWeekStart),
        appInfo: appInfo,
      ),
    ),
  );
}

class NextWeekPreviewPage extends StatefulWidget {
  const NextWeekPreviewPage({
    super.key,
    required this.nextWeekStartFuture,
    required this.appInfo,
    this.loadDatedWeek,
    this.onNextWeekMealRefreshed,
  });

  final Future<String?> nextWeekStartFuture;
  final Future<AppInfo> appInfo;
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
    _nextWeekStartFuture = widget.nextWeekStartFuture;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FutureBuilder<String?>(
      future: _nextWeekStartFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _MessageScaffold(
            title: l10n.nextWeekPreview,
            child: CircularProgressIndicator.adaptive(
              // 밝은 surface에서는 더 어두운 primary를 사용해 비텍스트 대비를
              // 확보하고, 다크 surface에서는 브랜드 primaryContainer를 유지한다.
              valueColor: AlwaysStoppedAnimation(
                theme.brightness == Brightness.light
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primaryContainer,
              ),
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
      appBar: AppBar(title: Text(title)),
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
        Provider.of<BapuSettings?>(
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
    final theme = Theme.of(context);
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
            child: CircularProgressIndicator.adaptive(
              // 밝은 surface에서는 더 어두운 primary를 사용해 비텍스트 대비를
              // 확보하고, 다크 surface에서는 브랜드 primaryContainer를 유지한다.
              valueColor: AlwaysStoppedAnimation(
                theme.brightness == Brightness.light
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primaryContainer,
              ),
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
          onPreviousWeekRequested: () async {
            await Navigator.of(context).maybePop();
          },
        );
      },
    );
  }
}
