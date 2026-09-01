import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 홈 화면 위젯 새로고침을 트리거한다.
///
/// foreground 호출은 기본적으로 실패를 로그만 남기지만, background refresh
/// 경로는 [throwOnFailure]를 켜서 Workmanager가 실패를 관찰할 수 있게 한다.
Future<void> refreshWidgets({bool throwOnFailure = false}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  try {
    await const MethodChannel(
      'pro.hexa.meal.meal_client/widget',
    ).invokeMethod<void>('refresh');
  } catch (e, stackTrace) {
    if (throwOnFailure) {
      Error.throwWithStackTrace(e, stackTrace);
    }
    debugPrint('[BapU] widget refresh trigger failed: $e');
    debugPrintStack(stackTrace: stackTrace);
  }
}

/// 앱 실행 시 홈 화면 위젯 새로고침을 트리거한다.
Future<void> updateHomeWidgets() {
  return refreshWidgets();
}
