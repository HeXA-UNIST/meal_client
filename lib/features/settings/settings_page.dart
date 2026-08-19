import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'app_settings.dart';
import 'allergy/allergy_settings_page.dart';
import 'notification/notification_settings_page.dart';

Future<void>? _fontLicenseRegistrationFuture;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Text(
          l10n.settings,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        children: [
          if (!kIsWeb) ...[
            if (kDebugMode) ...[
              _SectionHeader(l10n.allergyWarning),
              _AllergyTile(),
              const Divider(indent: 16, endIndent: 16),
            ],
            _SectionHeader(l10n.mealNotifications),
            _MealNotificationTile(),
            const Divider(indent: 16, endIndent: 16),
          ],
          _SectionHeader(l10n.themeMode),
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
        MaterialPageRoute(builder: (_) => const AllergySettingsPage()),
      ),
    );
  }
}

class _MealNotificationTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(l10n.notificationSettings),

      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MealNotificationPage()),
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
            value: ThemeMode.system,
            label: Text(l10n.themeModeSystem),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            label: Text(l10n.themeModeLight),
          ),
          ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeModeDark)),
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
        await (_fontLicenseRegistrationFuture ??= rootBundle
            .loadString('assets/fonts/Pretendard-License.txt')
            .then((fontLicense) {
              LicenseRegistry.addLicense(
                () => Stream<LicenseEntry>.value(
                  LicenseEntryWithLineBreaks(['Pretendard'], fontLicense),
                ),
              );
            }));
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
