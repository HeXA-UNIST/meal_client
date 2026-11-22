package pro.hexa.meal.meal_client

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 권한 허용 뒤 위젯과 식단 알림을 기존 캐시에서 복구한다. */
class BapUWidgetExactAlarmPermissionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) return
        if (!BapUWidgetScheduleManager.canScheduleExactAlarms(context)) return
        BapUNotificationPermissionRecovery.invalidateScheduleGeneration(context)
        // 위젯이 없는 알림 사용자도 복구한다. 서버 갱신 성공과 무관한 별도 작업이다.
        BapUNotificationPermissionRecovery.enqueue(context)
        if (!BapUWidgetUpdateDispatcher.hasAnyWidget(context)) return

        val pending = goAsync()
        BapUWidgetUpdateDispatcher.enqueueRenderAllWidgets(context) {
            // 오류 기록은 dispatcher가 맡고, 이 콜백은 수명 종료만 처리한다.
            pending.finish()
        }
    }
}
