package pro.hexa.meal.meal_client

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** 권한 허용 뒤 위젯과 식단 알림을 기존 캐시에서 복구한다. */
class BapUWidgetExactAlarmPermissionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) return
        if (!BapUWidgetScheduleManager.canScheduleExactAlarms(context)) return
        // 위젯이 없는 알림 사용자도 복구한다. 서버 갱신 성공과 무관한 별도 작업이다.
        BapUNotificationPermissionRecovery.enqueue(context)
        if (!BapUWidgetUpdateDispatcher.hasAnyWidget(context)) return

        val pending = goAsync()
        BapUWidgetUpdateDispatcher.enqueueRenderAllWidgets(context) { failure ->
            try {
                if (failure != null) Log.e(TAG, "widget restore after permission grant failed", failure)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private const val TAG = "BapUWidgetExactAlarm"
    }
}
