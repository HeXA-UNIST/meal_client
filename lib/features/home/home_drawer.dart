import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/announcement_state.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_data_source.dart';
import 'package:meal_client/features/settings/settings_page.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'next_week_preview_page.dart';

class HomeAnnouncementDialog extends StatelessWidget {
  final String close;
  final String title;
  final String content;

  const HomeAnnouncementDialog({
    super.key,
    required this.close,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: AlertDialog(
        shape: _dialogShape(),
        title: _HomeDialogTitle(title: title),
        content: SingleChildScrollView(
          child: ListBody(children: [Text(content)]),
        ),
        actions: [
          SelectionContainer.disabled(
            child: TextButton(
              child: Text(close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeDialogTitle extends StatelessWidget {
  final String title;

  const _HomeDialogTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset(
          'assets/imgs/bapu_logo.svg',
          height: 24,
          colorFilter: ColorFilter.mode(
            theme.colorScheme.primaryContainer,
            BlendMode.srcIn,
          ),
        ),
        SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center),
      ],
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 40, right: 16),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeOperationHoursDialog extends StatelessWidget {
  final String close;
  final String title;
  final OperatingHours operatingHours;

  const HomeOperationHoursDialog({
    super.key,
    required this.close,
    required this.title,
    required this.operatingHours,
  });

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: AlertDialog(
        shape: _dialogShape(),
        title: _HomeDialogTitle(title: title),
        contentPadding: EdgeInsets.fromLTRB(24, 14, 24, 8),
        content: SingleChildScrollView(
          child: _OperationHoursDialogContent(operatingHours: operatingHours),
        ),
        actions: [
          SelectionContainer.disabled(
            child: TextButton(
              child: Text(close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationHoursDialogContent extends StatelessWidget {
  final OperatingHours operatingHours;

  const _OperationHoursDialogContent({required this.operatingHours});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_hasAnyHours(operatingHours.weekday) &&
        !_hasAnyHours(operatingHours.weekend)) {
      return Text(l10n.noOperationHours, textAlign: TextAlign.center);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OperationHoursPeriodSection(
          title: l10n.weekday,
          period: operatingHours.weekday,
        ),
        SizedBox(height: 18),
        _OperationHoursPeriodSection(
          title: l10n.weekend,
          period: operatingHours.weekend,
        ),
      ],
    );
  }
}

class _OperationHoursPeriodSection extends StatelessWidget {
  final String title;
  final OperatingHoursPeriod period;

  const _OperationHoursPeriodSection({
    required this.title,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entries = Cafeteria.values
        .map(
          (cafeteria) => _OperationHoursCafeteriaEntry(
            cafeteria: cafeteria,
            period: period,
          ),
        )
        .where((entry) => entry.hasHours)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            l10n.noOperationHours,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...entries.expand(
            (entry) => [entry, if (entry != entries.last) SizedBox(height: 10)],
          ),
      ],
    );
  }
}

class _OperationHoursCafeteriaEntry extends StatelessWidget {
  final Cafeteria cafeteria;
  final OperatingHoursPeriod period;

  const _OperationHoursCafeteriaEntry({
    required this.cafeteria,
    required this.period,
  });

  bool get hasHours {
    return MealOfDay.values.any((mealOfDay) {
      return period.timeFor(cafeteria, mealOfDay) != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mealLabelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.1,
    );
    final timeStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _cafeteriaName(l10n, cafeteria),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4),
        Center(
          child: IntrinsicWidth(
            child: Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FixedColumnWidth(20),
                2: IntrinsicColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final mealOfDay in MealOfDay.values)
                  if (period.timeFor(cafeteria, mealOfDay) case final time?)
                    TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.zero,
                          child: Text(
                            _mealOfDayName(l10n, mealOfDay),
                            textAlign: TextAlign.end,
                            style: mealLabelStyle,
                          ),
                        ),
                        SizedBox(),
                        Padding(
                          padding: EdgeInsets.zero,
                          child: Text(time.label, style: timeStyle),
                        ),
                      ],
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class HomePageDrawer extends StatefulWidget {
  final Future<AppInfo>? infoFuture;
  final Future<String?>? nextWeekStart;

  const HomePageDrawer({super.key, this.infoFuture, this.nextWeekStart});

  @override
  State<HomePageDrawer> createState() => _HomePageDrawerState();
}

class _HomePageDrawerState extends State<HomePageDrawer> {
  late Future<AppInfo> _infoFuture;
  late Future<String?> _nextWeekStart;

  @override
  void initState() {
    super.initState();
    _infoFuture = widget.infoFuture ?? fetchAppInfo();
    _nextWeekStart = widget.nextWeekStart ?? Future.value(null);
  }

  @override
  void didUpdateWidget(covariant HomePageDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.infoFuture != oldWidget.infoFuture) {
      _infoFuture = widget.infoFuture ?? fetchAppInfo();
    }
    if (widget.nextWeekStart != oldWidget.nextWeekStart) {
      _nextWeekStart = widget.nextWeekStart ?? Future.value(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final l10n = AppLocalizations.of(context)!;

    return Drawer(
      width: 292,
      shape: _drawerShape(context),
      backgroundColor: brightness == Brightness.light
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainer,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 130,
            alignment: Alignment.bottomLeft,
            margin: EdgeInsets.only(bottom: 50, left: 40),
            child: SvgPicture.asset('assets/imgs/bapu_logo.svg', height: 36),
          ),
          _DrawerItem(
            icon: Icons.settings_outlined,
            title: l10n.settings,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.calendar_month_outlined,
            title: l10n.nextWeekPreview,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NextWeekPreviewPage(
                    nextWeekStartFuture: _nextWeekStart,
                    appInfo: _infoFuture,
                  ),
                ),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.notifications_active,
            title: l10n.announcement,
            onTap: () async {
              final rootNavigator = Navigator.of(context, rootNavigator: true);
              final rootContext = rootNavigator.context;
              Navigator.of(context).pop();
              var announcement = await getStoredAnnouncement();
              announcement ??= (await _infoFuture).announcement;
              if (announcement != null && rootContext.mounted) {
                final dialogL10n = AppLocalizations.of(rootContext)!;
                final languageCode = Localizations.localeOf(
                  rootContext,
                ).languageCode;
                showDialog(
                  context: rootContext,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return HomeAnnouncementDialog(
                      close: dialogL10n.close,
                      title:
                          announcement!.title?.textFor(languageCode) ??
                          dialogL10n.announcement,
                      content: announcement.content.textFor(languageCode),
                    );
                  },
                );
              } else if (rootContext.mounted) {
                final dialogL10n = AppLocalizations.of(rootContext)!;
                showDialog(
                  context: rootContext,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return HomeAnnouncementDialog(
                      close: dialogL10n.close,
                      title: dialogL10n.announcement,
                      content: dialogL10n.noAnnouncement,
                    );
                  },
                );
              }
            },
          ),
          _DrawerItem(
            icon: Icons.access_time,
            title: l10n.operationHours,
            onTap: () async {
              final rootNavigator = Navigator.of(context, rootNavigator: true);
              final rootContext = rootNavigator.context;
              Navigator.of(context).pop();
              try {
                final appInfo = await _infoFuture;
                if (rootContext.mounted) {
                  final dialogL10n = AppLocalizations.of(rootContext)!;
                  showDialog(
                    context: rootContext,
                    barrierDismissible: false,
                    builder: (BuildContext context) {
                      return HomeOperationHoursDialog(
                        close: dialogL10n.close,
                        title: dialogL10n.operationHours,
                        operatingHours: appInfo.operatingHours,
                      );
                    },
                  );
                }
              } on Object {
                if (rootContext.mounted) {
                  final dialogL10n = AppLocalizations.of(rootContext)!;
                  showDialog(
                    context: rootContext,
                    barrierDismissible: false,
                    builder: (BuildContext context) {
                      return HomeAnnouncementDialog(
                        close: dialogL10n.close,
                        title: dialogL10n.operationHours,
                        content: dialogL10n.cannotLoadOperationHours,
                      );
                    },
                  );
                }
              }
            },
          ),
          _DrawerItem(
            icon: Icons.help_outline_outlined,
            title: l10n.contactDeveloper,
            onTap: () async =>
                await launchUrl(Uri.parse("https://pf.kakao.com/_xcaYlxj")),
          ),
          const SafeArea(top: false, child: SizedBox(height: 12)),
        ],
      ),
    );
  }
}

// RoundedSuperellipseBorder는 iOS 스타일(스퀴클)이므로 iOS에서만 적용하고,
// 그 외 플랫폼에서는 일반 RoundedRectangleBorder를 사용한다.
ShapeBorder _dialogShape() {
  final borderRadius = BorderRadius.circular(28);
  return defaultTargetPlatform == TargetPlatform.iOS
      ? RoundedSuperellipseBorder(borderRadius: borderRadius)
      : RoundedRectangleBorder(borderRadius: borderRadius);
}

// 화면 실측 모서리 반경을 드로어 오른쪽(왼쪽 화면 가장자리와 맞닿지 않는 쪽) 모서리에만 적용한다.
// 왼쪽은 건드리지 않음(항상 0 유지). displayCornerRadii를 못 구하는 기기에서는
// M3 기본값(16)으로 대체한다. 곡선 종류(superellipse)는 iOS에서만 사용한다.
ShapeBorder _drawerShape(BuildContext context) {
  const fallbackRadius = Radius.circular(16);
  final displayCornerRadii = MediaQuery.displayCornerRadiiOf(context);
  final isLtr = Directionality.of(context) == TextDirection.ltr;
  final topRight = displayCornerRadii?.topRight ?? fallbackRadius;
  final bottomRight = displayCornerRadii?.bottomRight ?? fallbackRadius;
  final topLeft = displayCornerRadii?.topLeft ?? fallbackRadius;
  final bottomLeft = displayCornerRadii?.bottomLeft ?? fallbackRadius;
  final borderRadius = isLtr
      ? BorderRadius.only(topRight: topRight, bottomRight: bottomRight)
      : BorderRadius.only(topLeft: topLeft, bottomLeft: bottomLeft);

  return defaultTargetPlatform == TargetPlatform.iOS
      ? RoundedSuperellipseBorder(borderRadius: borderRadius)
      : RoundedRectangleBorder(borderRadius: borderRadius);
}

String _cafeteriaName(AppLocalizations l10n, Cafeteria cafeteria) {
  return switch (cafeteria) {
    Cafeteria.dormitory => l10n.dormitoryCafeteria,
    Cafeteria.student => l10n.studentCafeteria,
    Cafeteria.faculty => l10n.facultyCafeteria,
  };
}

String _mealOfDayName(AppLocalizations l10n, MealOfDay mealOfDay) {
  return switch (mealOfDay) {
    MealOfDay.breakfast => l10n.breakfast,
    MealOfDay.lunch => l10n.lunch,
    MealOfDay.dinner => l10n.dinner,
  };
}

bool _hasAnyHours(OperatingHoursPeriod period) {
  return Cafeteria.values.any((cafeteria) {
    return MealOfDay.values.any((mealOfDay) {
      return period.timeFor(cafeteria, mealOfDay) != null;
    });
  });
}
