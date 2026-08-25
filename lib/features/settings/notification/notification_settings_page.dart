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
import 'notification_settings.dart' show DormMealType, NotificationSettings;

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
  Animation<double>? _watchedRouteAnimation;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController();
    _keywordFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 알림을 켜지 않았으면 권한이 없는 게 정상이라 확인할 이유가 없다.
      // 사용자가 켜 둔 뒤 OS에서 권한을 회수한 경우만 확인하면 된다.
      if (!context.read<AppSettings>().notification.enabled) return;
      _refreshAuthorizationAfterTransition();
    });
  }

  @override
  void dispose() {
    _watchedRouteAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _keywordController.dispose();
    _keywordFocusNode.dispose();
    super.dispose();
  }

  /// 권한 조회는 플랫폼 채널 왕복과 notifyListeners 리빌드를 동반한다.
  /// 화면 전환 애니메이션 도중에 실행하면 프레임을 떨어뜨리므로 전환이 끝난 뒤로 미룬다.
  void _refreshAuthorizationAfterTransition() {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _refreshAuthorization();
      return;
    }
    _watchedRouteAnimation = animation;
    animation.addStatusListener(_handleRouteAnimationStatus);
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _watchedRouteAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _watchedRouteAnimation = null;
    if (!mounted) return;
    _refreshAuthorization();
  }

  void _refreshAuthorization() {
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
      appBar: AppBar(title: Text(l10n.notificationSettings)),
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
          // 알림을 켜지 않은 상태(설치 직후 등)에서는 권한이 없는 게 정상이므로
          // 별도 안내를 띄우지 않는다. 권한 거부는 토글 시 SnackBar로 안내한다.
          // 여기서는 앱 안에서는 켜 두었는데 시스템에서 권한이 꺼진, 알림이
          // 조용히 오지 않는 상태만 노출한다.
          if (notification.enabled &&
              authorizationStatus ==
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
          // 상위 알림 스위치가 꺼져도 종속 설정을 숨기지 않고 비활성 상태로 유지한다.
          // 전체를 반투명 레이어로 덮으면 페이지 합성 비용이 커지므로,
          // 각 위젯이 Material 기본 disabled 표현을 쓰도록 enabled를 내려준다.
          Column(
            children: [
              // 시간대별 알림 설정 (아침·점심·저녁·밤)
              const Divider(height: 28, indent: 16, endIndent: 16),
              _SubGroupLabel(
                l10n.notificationTimesLabel,
                enabled: notification.enabled,
              ),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              for (final period in MealNotificationPeriod.values)
                _PeriodAlertRow(
                  period: period,
                  sectionEnabled: notification.enabled,
                ),
              // 알림 받을 요일 선택 (월화수목금토일)
              const Divider(height: 28, indent: 16, endIndent: 16),
              _SubGroupLabel(
                l10n.notificationDaysLabel,
                enabled: notification.enabled,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const maxDayRowWidth = 560.0;
                    final rowWidth = constraints.maxWidth > maxDayRowWidth
                        ? maxDayRowWidth
                        : constraints.maxWidth;
                    // 각 칸 너비는 여기서 이미 확정되므로 _DayToggle 안에서
                    // 다시 LayoutBuilder로 재는 대신 지름을 계산해 넘긴다.
                    final cellWidth = rowWidth / _notificationDayOrder.length;
                    final diameter = cellWidth < _dayToggleMaxDiameter
                        ? cellWidth
                        : _dayToggleMaxDiameter;
                    return Center(
                      child: SizedBox(
                        width: rowWidth,
                        child: Row(
                          children: [
                            for (final day in _notificationDayOrder)
                              Expanded(
                                child: _DayToggle(
                                  label: _dayLabel(l10n, day),
                                  diameter: diameter,
                                  enabled: notification.enabled,
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
              _SubGroupLabel(
                l10n.notificationCafeteriasLabel,
                enabled: notification.enabled,
              ),
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
                        onSelected: notification.enabled
                            ? (checked) {
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
                              }
                            : null,
                      ),
                    for (final cafeteria in Cafeteria.values.where(
                      (c) => c != Cafeteria.dormitory,
                    ))
                      FilterChip(
                        label: Text(_cafeteriaName(l10n, cafeteria)),
                        selected: notification.cafeterias.contains(cafeteria),
                        onSelected: notification.enabled
                            ? (checked) {
                                final current = notification.cafeterias;
                                final next = checked
                                    ? {...current, cafeteria}
                                    : current
                                          .where((c) => c != cafeteria)
                                          .toSet();
                                // 최소 1개는 선택 유지
                                if (next.isNotEmpty ||
                                    notification.dormMealTypes.isNotEmpty) {
                                  context
                                      .read<AppSettings>()
                                      .setNotificationCafeterias(next);
                                }
                              }
                            : null,
                      ),
                  ],
                ),
              ),
              // 키워드 기능은 알림 기능 최초 배포 이후 잘 작동하면 도입
              if (kDebugMode) ...[
                // 키워드 입력 + 추가 버튼
                const Divider(height: 28, indent: 16, endIndent: 16),
                _SubGroupLabel(
                  l10n.notificationKeywordLabel,
                  enabled: notification.enabled,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keywordController,
                          focusNode: _keywordFocusNode,
                          enabled: notification.enabled,
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
                        onPressed: notification.enabled ? _submitKeyword : null,
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
                            onDeleted: notification.enabled
                                ? () => context
                                      .read<AppSettings>()
                                      .removeNotificationKeyword(kw)
                                : null,
                          ),
                      ],
                    ),
                  ),
              ],
            ],
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
    // CupertinoSwitch는 onChanged가 null이면 스스로 투명도를 낮춰 비활성을 표현한다.
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: activeTrackColor,
    );
  }
  // Material Switch는 명시한 activeTrackColor를 disabled 기본색보다 먼저 적용해,
  // 켜진 채로 비활성이 되면 색이 그대로 남는다. 비활성일 때는 넘기지 않는다.
  return Switch(
    value: value,
    onChanged: onChanged,
    activeTrackColor: onChanged == null ? null : activeTrackColor,
  );
}

/// 알림 섹션 내부 소제목 (알림 시간 / 알림 받을 요일 / 알림 대상 식당).
class _SubGroupLabel extends StatelessWidget {
  const _SubGroupLabel(this.label, {required this.enabled});

  final String label;
  final bool enabled;

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
            color: enabled
                ? theme.colorScheme.onSurfaceVariant
                : theme.disabledColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

const _dayToggleMaxDiameter = 42.0;

/// 요일별 알림 on/off를 위한 원형 토글 버튼.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.diameter,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double diameter;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final disabledColor = theme.disabledColor;
    // 비활성이어도 선택 여부는 계속 구분되어야 하므로 채움/외곽선은 유지하고
    // 색만 disabled 톤으로 낮춘다.
    final fillColor = selected
        ? (enabled ? scheme.primary : disabledColor.withValues(alpha: 0.12))
        : Colors.transparent;
    final borderColor = enabled
        ? (selected ? scheme.primary : scheme.outlineVariant)
        : disabledColor;
    final labelColor = enabled
        ? (selected ? scheme.onPrimary : scheme.onSurfaceVariant)
        : disabledColor;
    return Center(
      child: Semantics(
        label: label,
        button: true,
        enabled: enabled,
        selected: selected,
        onTap: enabled ? onTap : null,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: Container(
              width: diameter,
              height: diameter,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fillColor,
                border: Border.all(color: borderColor),
              ),
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: labelColor,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodAlertRow extends StatelessWidget {
  const _PeriodAlertRow({required this.period, required this.sectionEnabled});

  final MealNotificationPeriod period;

  /// 상위 "식단 알림" 스위치 상태. 꺼져 있으면 행 전체를 비활성으로 그린다.
  final bool sectionEnabled;

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
    // AppSettings 전체를 watch하면 권한 상태·동기화 실패 같은 무관한 알림에도
    // 시간대 행 4개가 모두 리빌드된다. 필요한 스냅샷만 구독한다.
    final notification = context.select<AppSettings, NotificationSettings>(
      (settings) => settings.notification,
    );
    // 선택 상태와 조작 가능 여부는 별개다. 상위 알림이 꺼져도 사용자가 저장해 둔
    // 시간대 선택은 "선택됨 + 비활성"으로 그대로 보여야 한다.
    final periodEnabled = notification.isPeriodEnabled(period);
    final displayTime = notification.displayTimeOf(period);
    final theme = Theme.of(context);

    // trailing에는 Switch만 두어 상단 "식단 알림" SwitchListTile과
    // 오른쪽 끝이 항상 같은 위치에 정렬되도록 한다. 시간 선택 드롭다운은
    // title 영역 안에 배치한다.
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 24, 0),
      title: Row(
        children: [
          Text(
            _label(l10n),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: sectionEnabled ? null : theme.disabledColor,
            ),
          ),
          const Spacer(),
          // ThemeData.copyWith는 60개가 넘는 필드를 복사한다. DropdownButton이
          // focusColor를 직접 받으므로 Theme 래퍼 없이 같은 결과를 낸다.
          DropdownButton<TimeOfDay>(
            focusColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            value: periodEnabled ? displayTime : null,
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
            onChanged: sectionEnabled && periodEnabled
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
      trailing: _platformSwitch(
        context,
        value: periodEnabled,
        onChanged: sectionEnabled
            ? (v) {
                // 켤 때는 마지막으로 선택했던 시각(없으면 기본 슬롯)으로 복원한다.
                final next = v ? displayTime : null;
                context.read<AppSettings>().setPeriodAlertTime(period, next);
              }
            : null,
      ),
    );
  }
}
