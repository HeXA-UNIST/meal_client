import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/core/constants.dart';

const mealRefreshTaskName = 'bapu_meal_refresh';
const mealRefreshTaskFrequency = Duration(hours: 2);
const _backgroundRefreshChannel = MethodChannel(
  'pro.hexa.meal.meal_client/meal_background_refresh',
);

/// 포그라운드 갱신을 모두 마친 뒤 기존 주기 작업의 다음 실행만 미룬다.
Future<void> postponeMealBackgroundRefresh() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  if (!await syncMealBackgroundRefresh()) return;
  if (Platform.isAndroid) {
    await _backgroundRefreshChannel.invokeMethod<void>(
      'postpone',
      DateTime.now().add(mealRefreshTaskFrequency).millisecondsSinceEpoch,
    );
  } else {
    await _registerMealBackgroundRefresh(
      initialDelay: mealRefreshTaskFrequency,
    );
  }
}

Future<void> initializeMealBackgroundRefresh() async {
  await syncMealBackgroundRefresh(updateExisting: true);
}

/// 사용 여부를 반환하고 Android 미사용 작업은 취소한다.
/// iOS는 앱 종료 후 추가된 위젯을 감지할 수 있도록 주기 예약을 유지한다.
Future<bool> syncMealBackgroundRefresh({bool updateExisting = false}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return false;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final notificationsEnabled =
        prefs.getBool(StorageKeys.notificationEnabled) ?? false;
    final needed =
        notificationsEnabled ||
        (await HomeWidget.getInstalledWidgets()).isNotEmpty;
    if (!needed && Platform.isAndroid) {
      await Workmanager().cancelByUniqueName(mealRefreshTaskName);
      return false;
    }
    // 복귀 때마다 iOS의 대기 시각을 다시 밀지 않고, 사라진 예약만 복구한다.
    final scheduled = await Workmanager().isScheduledByUniqueName(
      mealRefreshTaskName,
    );
    if (!scheduled || (updateExisting && Platform.isAndroid)) {
      await _registerMealBackgroundRefresh();
    }
    return needed;
  } catch (error, stackTrace) {
    // 위젯 조회 실패를 미사용으로 간주해 기존 갱신을 끊지 않는다.
    debugPrint('[BapU] background refresh scheduling failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return true;
  }
}

Future<void> _registerMealBackgroundRefresh({Duration? initialDelay}) async {
  // Workmanager 초기화는 앱의 단일 callbackDispatcher에서 수행한다.
  await Workmanager().registerPeriodicTask(
    mealRefreshTaskName,
    mealRefreshTaskName,
    frequency: mealRefreshTaskFrequency,
    initialDelay: initialDelay,
    // iOS BGAppRefreshTask는 Workmanager 네트워크 제약을 강제하지 않는다.
    constraints: Platform.isAndroid
        ? Constraints(networkType: NetworkType.connected)
        : null,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}
