import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:app_settings/app_settings.dart' as device_settings;
import 'package:meal_client/features/notification/meal_notification_period.dart';
import 'package:meal_client/features/notification/notification_service.dart';
import '../app_settings.dart';
import 'notification_settings.dart' show DormMealType;

/// 식단 알림(키워드·시간대·요일·대상 식당) 전용 설정 페이지.
class MealNotificationPage extends StatefulWidget {
  const MealNotificationPage({super.key});

  @override
  State<MealNotificationPage> createState() => _MealNotificationPageState();
}

// StatefulWidget: TextEditingController를 build() 밖에서 관리해
// 리빌드 시 입력 중인 텍스트가 초기화되지 않게 한다.
class _MealNotificationPageState extends State<MealNotificationPage> {
  late final TextEditingController _keywordController;
  late final FocusNode _keywordFocusNode;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController();
    _keywordFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        context
            .read<AppSettings>()
            .refreshNotificationAuthorizationStatus()
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                '[BapU] notification settings authorization refresh failed: $error',
              );
              debugPrintStack(stackTrace: stackTrace);
            }),
      );
    });
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
  void _openNotificationSettings() =>
      device_settings.AppSettings.openAppSettings(
        type: device_settings.AppSettingsType.notification,
      );

  Future<void> _handleNotificationToggle(bool enable) async {
    final result = await context.read<AppSettings>().setNotificationEnabled(
      enable,
    );
    if (!mounted) return;
    if (enable && result != NotificationEnableResult.enabled) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == NotificationEnableResult.permissionDenied
                ? l10n.notificationPermissionDenied
                : l10n.notificationSyncFailed,
          ),
          action: result == NotificationEnableResult.permissionDenied
              ? SnackBarAction(
                  label: l10n.openSystemAppSettings,
                  onPressed: _openNotificationSettings,
                )
              : SnackBarAction(
                  label: l10n.retry,
                  onPressed: () => unawaited(_handleNotificationToggle(true)),
                ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final appSettings = context.watch<AppSettings>();
    final notification = appSettings.notification;
    final authorizationStatus = appSettings.notificationAuthorizationStatus;
    return Scaffold(
      appBar: AppBar(
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
            title: Text(l10n.mealNotifications),
            subtitle: Text(l10n.notificationDescription),
            trailing: _platformSwitch(
              context,
              value: notification.enabled,
              onChanged: _handleNotificationToggle,
            ),
            onTap: () => _handleNotificationToggle(!notification.enabled),
          ),
          if (authorizationStatus ==
              MealNotificationAuthorizationStatus.notAuthorized)
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 24, 4),
              leading: const Icon(Icons.notifications_off_outlined),
              title: Text(l10n.notificationPermissionUnavailable),
              trailing: TextButton(
                onPressed: _openNotificationSettings,
                child: Text(l10n.openSystemAppSettings),
              ),
            ),
          if (appSettings.notificationSyncFailed)
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 24, 4),
              leading: const Icon(Icons.sync_problem_outlined),
              title: Text(l10n.notificationSyncFailed),
              trailing: TextButton(
                onPressed: () => unawaited(
                  context.read<AppSettings>().retryNotificationSync(),
                ),
                child: Text(l10n.retry),
              ),
            ),
          _NotificationOptions(
            enabled: notification.enabled,
            child: Column(
              children: [
                // 시간대별 알림 설정 (아침·점심·저녁·밤)
                const Divider(height: 28, indent: 16, endIndent: 16),
                _SubGroupLabel(l10n.notificationTimesLabel),
                if (notification.enabled &&
                    appSettings.usesInexactNotificationTiming)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 24, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.androidNotificationTimingNotice,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.brightness == Brightness.dark
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                if (notification.enabled && notification.activePeriods.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Text(
                      l10n.notificationTimeSelectionRequired,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                for (final period in MealNotificationPeriod.values)
                  _PeriodAlertRow(period: period),
                // 알림 받을 요일 선택 (월화수목금토일)
                const Divider(height: 28, indent: 16, endIndent: 16),
                _SubGroupLabel(l10n.notificationDaysLabel),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const maxDayRowWidth = 560.0;
                      final rowWidth = constraints.maxWidth > maxDayRowWidth
                          ? maxDayRowWidth
                          : constraints.maxWidth;
                      return Center(
                        child: SizedBox(
                          width: rowWidth,
                          child: Row(
                            children: [
                              for (final day in _notificationDayOrder)
                                Expanded(
                                  child: _DayToggle(
                                    label: _dayLabel(l10n, day),
                                    selected: notification.isDayEnabled(day),
                                    onTap: () {
                                      final current = notification.days;
                                      final next = current.contains(day)
                                          ? current
                                                .where((d) => d != day)
                                                .toSet()
                                          : {...current, day};
                                      // 최소 1개 요일은 유지
                                      if (next.isNotEmpty) {
                                        context
                                            .read<AppSettings>()
                                            .setNotificationDays(next);
                                      }
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
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
                            l10n.cafeteriaWithMealType(
                              l10n.dormitoryCafeteria,
                              _dormMealTypeName(l10n, dormMealType),
                            ),
                          ),
                          selected: notification.isDormMealTypeEnabled(
                            dormMealType,
                          ),
                          onSelected: (checked) {
                            final current = notification.dormMealTypes;
                            final next = checked
                                ? {...current, dormMealType}
                                : current
                                      .where((t) => t != dormMealType)
                                      .toSet();
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
                // 키워드 기능은 알림 기능 최초 배포 이후 잘 작동하면 도입
                if (kDebugMode) ...[
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
                          tooltip: l10n.addNotificationKeyword,
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
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 요일 토글 표시 순서: 월화수목금토일
const List<DayOfWeek> _notificationDayOrder = [
  DayOfWeek.mon,
  DayOfWeek.tue,
  DayOfWeek.wed,
  DayOfWeek.thu,
  DayOfWeek.fri,
  DayOfWeek.sat,
  DayOfWeek.sun,
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

Widget _platformSwitch(
  BuildContext context, {
  required bool value,
  required ValueChanged<bool>? onChanged,
}) {
  final activeTrackColor = Theme.of(context).colorScheme.primary;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: activeTrackColor,
    );
  }
  return Switch(
    value: value,
    onChanged: onChanged,
    activeTrackColor: activeTrackColor,
  );
}

/// 상위 알림 스위치가 꺼져도 종속 설정을 숨기지 않고 비활성 상태로 유지한다.
class _NotificationOptions extends StatelessWidget {
  const _NotificationOptions({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      enabled: enabled,
      child: ExcludeFocus(
        excluding: !enabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.38,
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        ),
      ),
    );
  }
}

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = constraints.maxWidth < 42.0
            ? constraints.maxWidth
            : 42.0;
        return Center(
          child: Semantics(
            label: label,
            button: true,
            selected: selected,
            onTap: onTap,
            child: ExcludeSemantics(
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: diameter,
                  height: diameter,
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
                      color: selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PeriodAlertRow extends StatelessWidget {
  const _PeriodAlertRow({required this.period});

  final MealNotificationPeriod period;

  String _label(AppLocalizations l10n) => switch (period) {
    MealNotificationPeriod.morning => l10n.breakfast,
    MealNotificationPeriod.lunch => l10n.lunch,
    MealNotificationPeriod.dinner => l10n.dinner,
    MealNotificationPeriod.night => l10n.notificationPeriodNight,
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
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 24, 0),
      title: Row(
        children: [
          Text(_label(l10n), style: theme.textTheme.bodyLarge),
          const Spacer(),
          Theme(
            data: theme.copyWith(
              focusColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            child: DropdownButton<TimeOfDay>(
              value: enabled ? displayTime : null,
              borderRadius: BorderRadius.circular(8),
              elevation: 2,
              dropdownColor: theme.colorScheme.surfaceContainer,
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
          ),
        ],
      ),
      trailing: _platformSwitch(
        context,
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
