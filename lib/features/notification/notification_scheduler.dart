import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:workmanager/workmanager.dart';

const kMealKeywordTaskName = 'meal_keyword_check';

/// 다음 [alertTime](기기 로컬 시각)까지 남은 시간을 초기 지연으로 설정하고,
/// 이후 24시간마다 반복 실행되는 Workmanager 태스크를 등록한다.
/// 기기 시간대가 KST로 설정되어 있다고 가정.
/// 1회성 태스크로 등록후 (Workmanager fix) 워커가 실행을 마치면 워커 자신이 다음날 같은 시각의
/// 태스크를 다시 등록
Future<void> scheduleKeywordNotification(TimeOfDay alertTime) async {
  try {
    await Workmanager().cancelByUniqueName(kMealKeywordTaskName);

    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day,
        alertTime.hour, alertTime.minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    final delay = next.difference(now);

    assert(() {
      debugPrint(
        '[BapU] notification scheduled at $next '
        '(in ${delay.inMinutes}m ${delay.inSeconds % 60}s)',
      );
      return true;
    }());

    await Workmanager().registerOneOffTask(
      kMealKeywordTaskName,
      kMealKeywordTaskName,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  } catch (e, st) {
    // unawaited로 호출되어 예외가 묻히지 않도록 로깅
    assert(() {
      debugPrint('[BapU] schedule failed: $e\n$st');
      return true;
    }());
    rethrow;
  }
}

Future<void> cancelKeywordNotification() =>
    Workmanager().cancelByUniqueName(kMealKeywordTaskName);
