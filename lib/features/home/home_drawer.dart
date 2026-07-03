import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/announcement/announcement_service.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/features/info/info_service.dart';
import 'package:meal_client/features/settings/settings_page.dart';
import 'package:meal_client/l10n/app_localizations.dart';

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
    final theme = Theme.of(context);
    return AlertDialog(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/imgs/bapu_logo.svg',
            height: 24,
            colorFilter: ColorFilter.mode(
              theme.colorScheme.primaryContainer,
              BlendMode.srcIn,
            ),
          ),
          SizedBox(height: 10),
          Text(title),
        ],
      ),
      content: SingleChildScrollView(
        child: ListBody(children: [Text(content)]),
      ),
      actions: [
        TextButton(
          child: Text(close),
          onPressed: () => Navigator.of(context).pop(),
        ),
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

class _OperationHoursSection extends StatelessWidget {
  final Future<AppInfo> infoFuture;
  final DateTime currentKstDate;

  const _OperationHoursSection({
    required this.infoFuture,
    required this.currentKstDate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            l10n.operationHours,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 16),
          FutureBuilder<AppInfo>(
            future: infoFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SizedBox.shrink();
              }
              if (!snapshot.hasData) {
                return SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                );
              }

              final period = snapshot.data!.operatingHours.forDate(currentKstDate);
              final entries = Cafeteria.values
                  .map((cafeteria) {
                    final hours = period.timesFor(cafeteria);
                    if (hours.isEmpty) {
                      return null;
                    }
                    return _OperationHoursEntry(
                      name: _cafeteriaName(l10n, cafeteria),
                      hours: hours.map((time) => time.label).toList(),
                    );
                  })
                  .nonNulls
                  .toList();

              return Column(
                children: [
                  for (final (index, entry) in entries.indexed) ...[
                    if (index > 0) SizedBox(height: 12),
                    entry,
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OperationHoursEntry extends StatelessWidget {
  final String name;
  final List<String> hours;

  const _OperationHoursEntry({required this.name, required this.hours});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 4),
        ...hours.map(
          (h) => Text(
            h,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class HomePageDrawer extends StatefulWidget {
  final Future<AppInfo>? infoFuture;
  final DateTime? currentKstDate;

  const HomePageDrawer({
    super.key,
    this.infoFuture,
    this.currentKstDate,
  });

  @override
  State<HomePageDrawer> createState() => _HomePageDrawerState();
}

class _HomePageDrawerState extends State<HomePageDrawer> {
  late Future<AppInfo> _infoFuture;

  @override
  void initState() {
    super.initState();
    _infoFuture = widget.infoFuture ?? fetchAppInfo();
  }

  @override
  void didUpdateWidget(covariant HomePageDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.infoFuture != oldWidget.infoFuture) {
      _infoFuture = widget.infoFuture ?? fetchAppInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final l10n = AppLocalizations.of(context)!;
    final currentKstDate =
        widget.currentKstDate ?? DateTime.now().toUtc().add(const Duration(hours: 9));

    return Drawer(
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
                final languageCode =
                    Localizations.localeOf(rootContext).languageCode;
                showDialog(
                  context: rootContext,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return HomeAnnouncementDialog(
                      close: dialogL10n.close,
                      title: announcement!.title?.textFor(languageCode) ??
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
            icon: Icons.help_outline_outlined,
            title: l10n.contactDeveloper,
            onTap: () async =>
                await launchUrl(Uri.parse("https://pf.kakao.com/_xcaYlxj")),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Divider(color: Colors.white54, height: 1),
          ),
          _OperationHoursSection(
            infoFuture: _infoFuture,
            currentKstDate: currentKstDate,
          ),
          const SafeArea(top: false, child: SizedBox(height: 12)),
        ],
      ),
    );
  }
}

String _cafeteriaName(AppLocalizations l10n, Cafeteria cafeteria) {
  return switch (cafeteria) {
    Cafeteria.dormitory => l10n.dormitoryCafeteria,
    Cafeteria.student => l10n.studentCafeteria,
    Cafeteria.faculty => l10n.facultyCafeteria,
  };
}
