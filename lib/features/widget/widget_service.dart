import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 앱 실행 시 홈 화면 위젯 새로고침을 트리거한다.
/// Android에서만 동작하며, WorkManager one-time job을 통해
/// 위젯 프로바이더들이 API에서 직접 최신 데이터를 가져온다.
Future<void> updateHomeWidgets() async {
  if (kIsWeb) return;
  if (!Platform.isAndroid) return;

  try {
    await const MethodChannel('pro.hexa.meal.meal_client/widget')
        .invokeMethod<void>('refresh');
  } catch (e) {
    assert(() {
      debugPrint('[BapU] widget refresh trigger failed: $e');
      return true;
    }());
  }
}
