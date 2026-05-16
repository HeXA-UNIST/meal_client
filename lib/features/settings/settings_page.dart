import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:app_settings/app_settings.dart' as device_settings;
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'app_settings.dart';
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
  late final FocusNode _keywordFocusNode;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController();
    _keywordFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _keywordFocusNode.dispose();
    super.dispose();
  }

  /// 현재 입력란의 텍스트를 키워드로 추가하고 입력란을 비운다.
  void _submitKeyword() {
    final text = _keywordController.text.trim();
    if (text.isEmpty) return;
    context.read<AppSettings>().addNotificationKeyword(text);
    _keywordController.clear();
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _cafeteriaName(AppLocalizations l10n, Cafeteria cafeteria) =>
      switch (cafeteria) {
        Cafeteria.dormitory => l10n.dormitoryCafeteria,
        Cafeteria.student   => l10n.studentCafeteria,
        Cafeteria.faculty   => l10n.facultyCafeteria,
      };

  // SwitchListTile.onChanged에 async 람다를 사용할 수 없어 별도 메서드로 분리.
  // 권한 거부 시 SnackBar로 안내하고 시스템 설정으로 이동 버튼을 제공한다.
  Future<void> _handleNotificationToggle(bool enable) async {
    if (!enable) {
      context.read<AppSettings>().setNotificationEnabled(false);
      return;
    }

    final granted = await requestNotificationPermission();
    if (!mounted) return;

    if (!granted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.notificationPermissionDenied),
          action: SnackBarAction(
            label: l10n.openSystemAppSettings,
            onPressed: () => device_settings.AppSettings.openAppSettings(
              type: device_settings.AppSettingsType.notification,
            ),
          ),
        ),
      );
      return;
    }

    context.read<AppSettings>().setNotificationEnabled(true);
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
            notification.keywords.isNotEmpty
                ? notification.keywords.map((k) => '"$k"').join(', ')
                : l10n.notificationKeywordHint,
          ),
          value: notification.enabled,
          onChanged: _handleNotificationToggle,
        ),
        if (notification.enabled) ...[
          // 키워드 입력 + 추가 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordController,
                    focusNode: _keywordFocusNode,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.notificationKeywordLabel,
                      hintText: l10n.notificationKeywordHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submitKeyword(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.notificationKeywordLabel,
                  onPressed: _submitKeyword,
                ),
              ],
            ),
          ),
          // 등록된 키워드 칩 목록
          if (notification.keywords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final kw in notification.keywords)
                    Chip(
                      label: Text(kw),
                      onDeleted: () => context
                          .read<AppSettings>()
                          .removeNotificationKeyword(kw),
                    ),
                ],
              ),
            ),
          // 알림 시간 선택
          ListTile(
            dense: true,
            title: Text(l10n.notificationTimeLabel),
            trailing: Text(
              _formatTime(notification.alertTime),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: notification.alertTime,
              );
              if (picked != null && context.mounted) {
                context.read<AppSettings>().setNotificationTime(picked);
              }
            },
          ),
          // 알림 대상 식당 선택
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.notificationCafeteriasLabel,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          for (final cafeteria in Cafeteria.values)
            CheckboxListTile(
              dense: true,
              title: Text(_cafeteriaName(l10n, cafeteria)),
              value: notification.cafeterias.contains(cafeteria),
              onChanged: (checked) {
                final current = notification.cafeterias;
                final next = checked == true
                    ? {...current, cafeteria}
                    : current.where((c) => c != cafeteria).toSet();
                // 최소 1개는 선택 유지
                if (next.isNotEmpty) {
                  context
                      .read<AppSettings>()
                      .setNotificationCafeterias(next);
                }
              },
            ),
        ],
        // 디버그 빌드에서만 표시되는 알림 즉시 테스트 버튼
        if (kDebugMode && notification.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('[DEV] 알림 지금 테스트'),
              onPressed: () async {
                // 저장된 키워드 + 현재 입력 중인 미저장 키워드까지 합쳐서 테스트
                final pending = _keywordController.text.trim();
                final keywords = [
                  ...notification.keywords,
                  if (pending.isNotEmpty &&
                      !notification.keywords.contains(pending))
                    pending,
                ];
                await testMealKeywordCheck(keywordsOverride: keywords);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        keywords.isEmpty
                            ? '키워드를 먼저 입력해주세요'
                            : '키워드 ${keywords.length}개로 체크 완료 (매칭 시 알림 발송됨)',
                      ),
                    ),
                  );
                }
              },
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
