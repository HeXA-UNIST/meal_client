import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../meal.dart';
import '../settings/app_settings.dart';
import 'allergy_selection_page.dart';

Future<void>? _fontLicenseRegistrationFuture;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          if (!kIsWeb) ...[
            _SectionHeader(l10n.allergyWarning),
            _AllergyTile(),
            const Divider(indent: 16, endIndent: 16),
            _SectionHeader(l10n.notificationSettings),
            _NotificationTile(),
            const Divider(indent: 16, endIndent: 16),
            _SectionHeader(l10n.widgetSettings),
            _WidgetCafeteriaTile(),
            const Divider(indent: 16, endIndent: 16),
          ],
          _SectionHeader(l10n.appearance),
          _ThemeTile(),
          const Divider(indent: 16, endIndent: 16),
          _SectionHeader(l10n.about),
          _LicenseTile(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge!.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _AllergyTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final count = context.watch<AppSettings>().allergy.enabledIds.length;
    return ListTile(
      title: Text(l10n.manageAllergies),
      subtitle: Text(
        count == 0
            ? l10n.noAllergenSelected
            : l10n.allergenSelectedCount(count),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AllergySelectionPage()),
      ),
    );
  }
}

// StatefulWidget: TextEditingController를 build() 밖에서 관리해
// 리빌드 시 입력 중인 텍스트가 초기화되지 않게 한다.
class _NotificationTile extends StatefulWidget {
  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  late final TextEditingController _keywordController;

  @override
  void initState() {
    super.initState();
    final keyword = context.read<AppSettings>().notification.keyword;
    _keywordController = TextEditingController(text: keyword);
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notification = context.watch<AppSettings>().notification;
    return Column(
      children: [
        SwitchListTile(
          title: Text(l10n.notificationSettings),
          subtitle: Text(
            notification.keyword.isNotEmpty
                ? '"${notification.keyword}"'
                : l10n.notificationKeywordHint,
          ),
          value: notification.enabled,
          onChanged: (v) =>
              context.read<AppSettings>().setNotificationEnabled(v),
        ),
        if (notification.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _keywordController,
              decoration: InputDecoration(
                labelText: l10n.notificationKeywordLabel,
                hintText: l10n.notificationKeywordHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) =>
                  context.read<AppSettings>().setNotificationKeyword(v),
            ),
          ),
      ],
    );
  }
}

class _WidgetCafeteriaTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cafeteria = context.watch<AppSettings>().widget.cafeteria;

    String cafeteriaName(Cafeteria c) => switch (c) {
          Cafeteria.dormitory => l10n.dormitoryCafeteria,
          Cafeteria.student   => l10n.studentCafeteria,
          Cafeteria.faculty   => l10n.facultyCafeteria,
        };

    return ListTile(
      title: Text(l10n.widgetCafeteriaLabel),
      trailing: DropdownButton<Cafeteria>(
        value: cafeteria,
        underline: const SizedBox(),
        items: Cafeteria.values
            .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(cafeteriaName(c)),
                ))
            .toList(),
        onChanged: (c) {
          if (c != null) context.read<AppSettings>().setWidgetCafeteria(c);
        },
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themeMode = context.watch<AppSettings>().themeMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<ThemeMode>(
        segments: [
          ButtonSegment(
              value: ThemeMode.system, label: Text(l10n.themeModeSystem)),
          ButtonSegment(
              value: ThemeMode.light, label: Text(l10n.themeModeLight)),
          ButtonSegment(
              value: ThemeMode.dark, label: Text(l10n.themeModeDark)),
        ],
        selected: {themeMode},
        onSelectionChanged: (v) =>
            context.read<AppSettings>().setThemeMode(v.first),
      ),
    );
  }
}

class _LicenseTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(l10n.openSourceLicenses),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await (_fontLicenseRegistrationFuture ??=
            rootBundle.loadString('assets/fonts/Pretendard-License.txt').then(
              (fontLicense) {
                LicenseRegistry.addLicense(
                  () => Stream<LicenseEntry>.value(
                    LicenseEntryWithLineBreaks(['Pretendard'], fontLicense),
                  ),
                );
              },
            ));
        if (!context.mounted) return;
        showLicensePage(
          context: context,
          applicationLegalese:
              'GPL-2.0 license. Source code: https://github.com/HeXA-UNIST/meal_client',
        );
      },
    );
  }
}
