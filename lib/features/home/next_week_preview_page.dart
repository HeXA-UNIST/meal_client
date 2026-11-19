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
  await Fluttertoast.cancel();
  await Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    timeInSecForIosWeb: 2,
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
  MealOfDay? initialMealOfDay,
}) async {
  final route = ModalRoute.of(context);
  final String? nextWeekStart;
  try {
    nextWeekStart = await nextWeekStartFuture;
  } catch (error, stackTrace) {
    debugPrint('[BapU] next week metadata fetch failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    if (!context.mounted || route?.isCurrent == false) return;
    await _showPreviewToast(
      context,
      AppLocalizations.of(context)!.cannotLoadMeal,
    );
    return;
  }
  if (!context.mounted || route?.isCurrent == false) return;
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
        nextWeekStart: nextWeekStart!,
        appInfo: appInfo,
        initialMealOfDay: initialMealOfDay,
      ),
    ),
  );
}

class NextWeekPreviewPage extends StatefulWidget {
  const NextWeekPreviewPage({
    super.key,
    required this.nextWeekStart,
    required this.appInfo,
    this.initialMealOfDay,
    this.loadDatedWeek,
    this.onNextWeekMealRefreshed,
  });

  final String nextWeekStart;
  final Future<AppInfo> appInfo;
  final MealOfDay? initialMealOfDay;
  final DatedWeekMealLoader? loadDatedWeek;
  final VoidCallback? onNextWeekMealRefreshed;

  @override
  State<NextWeekPreviewPage> createState() => _NextWeekPreviewPageState();
}

class _NextWeekPreviewPageState extends State<NextWeekPreviewPage> {
  late final DateTime _mondayOfWeek;
  late final Future<WeekMeal> _mealFuture;

  @override
  void initState() {
    super.initState();
    _mondayOfWeek = parseWeekStartDate(widget.nextWeekStart);
    _mealFuture =
        (widget.loadDatedWeek ?? fetchAndCacheMealDataForWeek)(
          widget.nextWeekStart,
        ).then((meal) {
          final callback = widget.onNextWeekMealRefreshed;
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
    // 식단 로딩·오류도 이 안에서 처리해 날짜·요일·끼니 선택을 계속 표시한다.
    return WeekMenuScaffold(
      mondayOfWeek: _mondayOfWeek,
      initialDayOfWeek: DayOfWeek.mon,
      initialMealOfDay: widget.initialMealOfDay ?? MealOfDay.breakfast,
      mealFuture: _mealFuture,
      appInfo: widget.appInfo,
      bannerText: l10n.previewingNextWeek,
      titleFontWeight: FontWeight.w600,
      onPreviousWeekRequested: () async {
        await Navigator.of(context).maybePop();
      },
    );
  }
}
