package pro.hexa.meal.meal_client

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** 권한 허용 뒤 기존 위젯 표시와 다음 예약을 현재 권한에 맞춰 복구한다. */
class BapUWidgetExactAlarmPermissionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) return
        if (!BapUWidgetScheduleManager.canScheduleExactAlarms(context)) return
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
