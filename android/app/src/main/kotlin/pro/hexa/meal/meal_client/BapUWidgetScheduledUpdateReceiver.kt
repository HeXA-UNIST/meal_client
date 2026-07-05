package pro.hexa.meal.meal_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * [BapUWidgetScheduleManager]가 예약한 시각 호출을 받아 위젯을 갱신하고, 다음 경계
 * 시점(또는 마감임박 중이면 다음 1분)에 대한 호출을 다시 예약한다.
 */
class BapUWidgetScheduledUpdateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                BapUWidgetUpdateDispatcher.renderAllWidgets(context)
            } catch (e: Exception) {
                Log.e(TAG, "scheduled update failed", e)
            } finally {
                // 위젯이 남아있는 한 계속 다음 호출을 예약한다.
                if (BapUWidgetUpdateDispatcher.hasAnyWidget(context)) {
                    BapUWidgetScheduleManager.scheduleNext(context)
                }
                pending.finish()
            }
        }.start()
    }

    companion object {
        private const val TAG = "BapUWidgetScheduledUpdate"
    }
}
