package pro.hexa.meal.meal_client

import com.google.firebase.crashlytics.FirebaseCrashlytics

internal fun reportNativeNonFatal(error: Throwable) {
    // profile도 제외하고, SDK에 접근하기 전에 개발 빌드의 직접 오류 기록을 막는다.
    if (BuildConfig.BUILD_TYPE != "release") return

    // 진단 실패가 위젯 갱신, 예약 복구와 완료 콜백을 방해하지 않게 한다.
    runCatching {
        val crashlytics = FirebaseCrashlytics.getInstance()
        if (crashlytics.isCrashlyticsCollectionEnabled) {
            crashlytics.recordException(error)
        }
    }
}
