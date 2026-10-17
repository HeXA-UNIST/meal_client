import 'dart:async' show unawaited;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:meal_client/l10n/app_localizations.dart';

import '../bapu_settings.dart';

/// 기존 알림 설정은 유지하면서 시스템 권한으로 중단된 상태를 계속 알린다.
class ExactAlarmPermissionNotice extends StatefulWidget {
  const ExactAlarmPermissionNotice({super.key});

  @override
  State<ExactAlarmPermissionNotice> createState() =>
      _ExactAlarmPermissionNoticeState();
}

class _ExactAlarmPermissionNoticeState
    extends State<ExactAlarmPermissionNotice> {
  bool _requesting = false;

  Future<void> _restore(BapuSettings settings) async {
    setState(() => _requesting = true);
    try {
      await settings.restoreNotificationPermission();
    } catch (error, stackTrace) {
      debugPrint('[BapU] notification permission recovery failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    // 시스템 권한 화면에서 돌아온 뒤 실제 Flutter 프레임에서 결과를 표시한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _requesting = false;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<BapuSettings?>();
    if (settings == null ||
        !settings.notification.enabled ||
        !settings.exactAlarmPermissionRequired) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.exactAlarmNotificationsPaused),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _requesting
                    ? null
                    : () => unawaited(_restore(settings)),
                child: Text(l10n.openExactAlarmSettings),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
