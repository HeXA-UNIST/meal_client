import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:app_settings/app_settings.dart' as device_settings;
import 'package:meal_client/features/notification/meal_alert_period.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'app_settings.dart';
import 'notification_settings.dart' show DormMealType;

/// 식단 알림(키워드·시간대·요일·대상 식당) 전용 설정 페이지.
class MealAlertPage extends StatefulWidget {
  const MealAlertPage({super.key});

  @override
  State<MealAlertPage> createState() => _MealAlertPageState();
}

// StatefulWidget: TextEditingController를 build() 밖에서 관리해
// 리빌드 시 입력 중인 텍스트가 초기화되지 않게 한다.
class _MealAlertPageState extends State<MealAlertPage> {
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

  String _cafeteriaName(AppLocalizations l10n, Cafeteria cafeteria) =>
      switch (cafeteria) {
        Cafeteria.dormitory => l10n.dormitoryCafeteria,
        Cafeteria.student => l10n.studentCafeteria,
        Cafeteria.faculty => l10n.facultyCafeteria,
      };

  String _dormMealTypeName(AppLocalizations l10n, DormMealType type) =>
      switch (type) {
        DormMealType.korean => l10n.menuKorean,
        DormMealType.halal => l10n.menuHalal,
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
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Text(l10n.notificationSettings),
      ),
      body: ListView(
        children: [
          // 아래 시간대별 행(_PeriodAlertRow)과 오른쪽 끝이 같은 위치에
          // 정렬되도록 SwitchListTile 대신 같은 contentPadding의 ListTile +
          // Switch를 직접 사용한다. SwitchListTile은 내부적으로 다른 여백을
          // 가지고 있어 그대로는 정렬이 맞지 않는다.
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 24, 4),
            title: Text(l10n.notificationSettings),
            subtitle: Text(
              notification.keywords.isNotEmpty
                  ? notification.keywords.map((k) => '"$k"').join(', ')
                  : l10n.notificationKeywordHint,
            ),
            trailing: Switch(
              value: notification.enabled,
              onChanged: _handleNotificationToggle,
            ),
            onTap: () => _handleNotificationToggle(!notification.enabled),
          ),
          if (notification.enabled) ...[
            // 시간대별 알림 설정 (아침·점심·저녁·밤)
            const Divider(height: 28, indent: 16, endIndent: 16),
            _SubGroupLabel(l10n.notificationTimeLabel),
            for (final period in MealAlertPeriod.values)
              _PeriodAlertRow(period: period),
            // 알림 받을 요일 선택 (일월화수목금토)
            const Divider(height: 28, indent: 16, endIndent: 16),
            _SubGroupLabel(l10n.notificationDaysLabel),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final day in _notificationDayOrder) ...[
                      if (day != _notificationDayOrder.first)
                        const SizedBox(width: 18),
                      _DayToggle(
                        label: _dayLabel(l10n, day),
                        selected: notification.isDayEnabled(day),
                        onTap: () {
                          final current = notification.days;
                          final next = current.contains(day)
                              ? current.where((d) => d != day).toSet()
                              : {...current, day};
                          // 최소 1개 요일은 유지
                          if (next.isNotEmpty) {
                            context
                                .read<AppSettings>()
                                .setNotificationDays(next);
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 알림 대상 식당 선택 (기숙사는 한식/할랄을 구분해서 선택)
            const Divider(height: 28, indent: 16, endIndent: 16),
            _SubGroupLabel(l10n.notificationCafeteriasLabel),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final dormMealType in DormMealType.values)
                    FilterChip(
                      label: Text(
                        '${l10n.dormitoryCafeteria} ${_dormMealTypeName(l10n, dormMealType)}',
                      ),
                      selected: notification.isDormMealTypeEnabled(
                        dormMealType,
                      ),
                      onSelected: (checked) {
                        final current = notification.dormMealTypes;
                        final next = checked
                            ? {...current, dormMealType}
                            : current.where((t) => t != dormMealType).toSet();
                        // 최소 1개는 선택 유지
                        if (next.isNotEmpty ||
                            notification.cafeterias.isNotEmpty) {
                          context
                              .read<AppSettings>()
                              .setNotificationDormMealTypes(next);
                        }
                      },
                    ),
                  for (final cafeteria in Cafeteria.values.where(
                    (c) => c != Cafeteria.dormitory,
                  ))
                    FilterChip(
                      label: Text(_cafeteriaName(l10n, cafeteria)),
                      selected: notification.cafeterias.contains(cafeteria),
                      onSelected: (checked) {
                        final current = notification.cafeterias;
                        final next = checked
                            ? {...current, cafeteria}
                            : current.where((c) => c != cafeteria).toSet();
                        // 최소 1개는 선택 유지
                        if (next.isNotEmpty ||
                            notification.dormMealTypes.isNotEmpty) {
                          context
                              .read<AppSettings>()
                              .setNotificationCafeterias(next);
                        }
                      },
                    ),
                ],
              ),
            ),
            // 키워드 입력 + 추가 버튼
            const Divider(height: 28, indent: 16, endIndent: 16),
            _SubGroupLabel(l10n.notificationKeywordLabel),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
          ],
          // 디버그 빌드에서만 표시되는 알림 즉시 테스트 버튼
          if (kDebugMode && notification.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                ),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 요일 토글 표시 순서: 일월화수목금토
const List<DayOfWeek> _notificationDayOrder = [
  DayOfWeek.sun,
  DayOfWeek.mon,
  DayOfWeek.tue,
  DayOfWeek.wed,
  DayOfWeek.thu,
  DayOfWeek.fri,
  DayOfWeek.sat,
];

String _dayLabel(AppLocalizations l10n, DayOfWeek day) => switch (day) {
  DayOfWeek.mon => l10n.mon,
  DayOfWeek.tue => l10n.tue,
  DayOfWeek.wed => l10n.wed,
  DayOfWeek.thu => l10n.thu,
  DayOfWeek.fri => l10n.fri,
  DayOfWeek.sat => l10n.sat,
  DayOfWeek.sun => l10n.sun,
};

/// 알림 섹션 내부 소제목 (알림 시간 / 알림 받을 요일 / 알림 대상 식당).
class _SubGroupLabel extends StatelessWidget {
  const _SubGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 요일별 알림 on/off를 위한 원형 토글 버튼.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PeriodAlertRow extends StatelessWidget {
  const _PeriodAlertRow({required this.period});

  final MealAlertPeriod period;

  String _label(AppLocalizations l10n) => switch (period) {
    MealAlertPeriod.morning => l10n.breakfast,
    MealAlertPeriod.lunch => l10n.lunch,
    MealAlertPeriod.dinner => l10n.dinner,
    MealAlertPeriod.night => l10n.notificationPeriodNight,
  };

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final notification = context.watch<AppSettings>().notification;
    final enabled = notification.isPeriodEnabled(period);
    final displayTime = notification.displayTimeOf(period);
    final theme = Theme.of(context);

    // trailing에는 Switch만 두어 상단 "식단 알림" SwitchListTile과
    // 오른쪽 끝이 항상 같은 위치에 정렬되도록 한다. 시간 선택 드롭다운은
    // title 영역 안에 배치한다.
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 24, 4),
      title: Row(
        children: [
          Text(_label(l10n), style: theme.textTheme.bodyLarge),
          const Spacer(),
          DropdownButton<TimeOfDay>(
            value: enabled ? displayTime : null,
            underline: const SizedBox(),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            disabledHint: Text(
              _formatTime(displayTime),
              style: TextStyle(color: theme.disabledColor),
            ),
            onChanged: enabled
                ? (slot) {
                    if (slot == null) return;
                    context.read<AppSettings>().setPeriodAlertTime(
                      period,
                      slot,
                    );
                  }
                : null,
            items: [
              for (final slot in period.allSlots)
                DropdownMenuItem(value: slot, child: Text(_formatTime(slot))),
            ],
          ),
        ],
      ),
      trailing: Switch(
        value: enabled,
        onChanged: (v) {
          // 켤 때는 마지막으로 선택했던 시각(없으면 기본 슬롯)으로 복원한다.
          final next = v ? displayTime : null;
          context.read<AppSettings>().setPeriodAlertTime(period, next);
        },
      ),
    );
  }
}
