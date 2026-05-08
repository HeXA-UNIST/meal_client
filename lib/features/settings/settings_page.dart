import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';
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
    final keyword = context.read<AppSettings>().notification.keyword;
    _keywordController = TextEditingController(text: keyword);
    _keywordFocusNode = FocusNode()
      ..addListener(() {
        if (!_keywordFocusNode.hasFocus) {
          context
              .read<AppSettings>()
              .setNotificationKeyword(_keywordController.text); // 추가
        }
      });
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _keywordFocusNode.dispose();
    super.dispose();
  }

  String _cafeteriaName(AppLocalizations l10n, Cafeteria cafeteria) =>
      switch (cafeteria) {
        Cafeteria.dormitory => l10n.dormitoryCafeteria,
        Cafeteria.student   => l10n.studentCafeteria,
        Cafeteria.faculty   => l10n.facultyCafeteria,
      };

  // Android 13+ 알림 권한 요청 후 활성화.
  // SwitchListTile.onChanged에 async 람다를 사용할 수 없어 별도 메서드로 분리.
  Future<void> _handleNotificationToggle(bool enable) async {
    if (enable) {
      final granted = await requestNotificationPermission();
      if (!granted || !mounted) return;
    }
    if (mounted) {
      context.read<AppSettings>().setNotificationEnabled(enable);
    }
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
          onChanged: _handleNotificationToggle,
        ),
        if (notification.enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _keywordController,
              focusNode: _keywordFocusNode,
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
                // SharedPreferences 저장 타이밍 문제를 피하기 위해
                // 현재 컨트롤러 값을 직접 전달
                final keyword = _keywordController.text.trim();
                await testMealKeywordCheck(keywordOverride: keyword);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        keyword.isEmpty
                            ? '키워드를 먼저 입력해주세요'
                            : '"$keyword" 알림 체크 완료 (매칭 시 알림 발송됨)',
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
