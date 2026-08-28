import 'package:app_settings/app_settings.dart' as device_settings;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'app_settings.dart';
import 'allergy/allergy_settings_page.dart';
import 'notification/notification_settings_page.dart';

Future<void>? _fontLicenseRegistrationFuture;

const _settingsHorizontalPadding = 16.0;
const _settingsSectionDividerHeight = 20.0;
const _settingsPageTopPadding = 8.0;
const _settingsPageBottomPadding = 16.0;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListTileTheme(
        data: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: _settingsHorizontalPadding,
          ),
          titleTextStyle: theme.textTheme.bodyLarge,
          subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.only(top: _settingsPageTopPadding),
          children: [
            if (!kIsWeb) ...[
              if (kDebugMode) ...[
                _SectionHeader(l10n.allergyWarning),
                _AllergyTile(),
                const _SectionDivider(),
              ],
              _SectionHeader(l10n.mealNotifications),
              _MealNotificationTile(),
              const _SectionDivider(),
              _SectionHeader(l10n.language),
              _LanguageTile(),
              const _SectionDivider(),
            ],
            _SectionHeader(l10n.themeMode),
            _ThemeTile(),
            const _SectionDivider(),
            _SectionHeader(l10n.about),
            _LicenseTile(),
            const SizedBox(height: _settingsPageBottomPadding),
          ],
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: _settingsSectionDividerHeight,
      indent: _settingsHorizontalPadding,
      endIndent: _settingsHorizontalPadding,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _settingsHorizontalPadding,
        4,
        _settingsHorizontalPadding,
        4,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelLarge!.copyWith(
          color: theme.colorScheme.primary,
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

class _LanguageTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(l10n.appLanguageSettings),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => device_settings.AppSettings.openAppSettings(
        type: switch (defaultTargetPlatform) {
          TargetPlatform.android => device_settings.AppSettingsType.appLocale,
          TargetPlatform.iOS => device_settings.AppSettingsType.settings,
          _ => device_settings.AppSettingsType.settings,
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _settingsHorizontalPadding,
        vertical: 8,
      ),
      child: SegmentedButton<ThemeMode>(
        style: ButtonStyle(
          textStyle: WidgetStateProperty.resolveWith((states) {
            return theme.textTheme.labelLarge?.copyWith(
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : null,
            );
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant;
          }),
        ),
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
