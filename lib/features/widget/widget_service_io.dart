import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// 홈 화면 위젯 새로고침을 트리거한다.
///
/// 갱신 요청 실패는 기본적으로 로그만 남기며, [throwOnFailure]가 켜져 있으면
/// 호출자에게 전달한다. Android에서는 broadcast 전송까지만 기다리므로
/// 실제 렌더·예약 실패는 네이티브 로그에만 남는다.
Future<void> refreshWidgets({bool throwOnFailure = false}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  try {
    // Android applicationId와 Kotlin 패키지가 다르므로 provider 전체 이름을 쓴다.
    final accepted = await HomeWidget.updateWidget(
      qualifiedAndroidName: 'pro.hexa.meal.meal_client.BapUWidget2x2Provider',
      iOSName: 'BapUWidget',
    );
    if (accepted != true) {
      throw StateError('Home widget update request was not accepted');
    }
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
