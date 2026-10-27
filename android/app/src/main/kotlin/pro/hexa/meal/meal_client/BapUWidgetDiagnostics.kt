package pro.hexa.meal.meal_client

import android.util.Log

/**
 * 오류를 처리한 경계에서 한 번만 기록한다. 완료 콜백에서는 같은 오류를 다시 보고하지 않는다.
 * Firebase 통합 시 이 지점에 원인 예외의 non-fatal 보고를 연결한다.
 * 여러 위젯이나 렌더·예약의 동시 실패를 놓치지 않도록 cause와 suppressed도 보존한다.
 */
internal fun logWidgetFailure(stage: String, error: Throwable) {
    // 진단 실패 때문에 예약 복구나 완료 콜백이 중단되지 않게 한다.
    runCatching { Log.e("BapUWidgetFailure", "stage=$stage", error) }
}
