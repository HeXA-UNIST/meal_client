package pro.hexa.meal.meal_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * [BapUWidgetScheduleManager]가 예약한 호출을 받아 위젯을 갱신하고 다음 표시 경계를 예약한다.
 */
class BapUWidgetScheduledUpdateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        BapUWidgetUpdateDispatcher.execute {
            try {
                BapUWidgetUpdateDispatcher.renderAllWidgetsLenient(context)
            } catch (e: Exception) {
                Log.e(TAG, "scheduled update failed", e)
            } finally {
                try {
                    // 위젯이 남아있는 한 계속 다음 호출을 예약한다.
                    if (BapUWidgetUpdateDispatcher.hasAnyWidget(context)) {
                        BapUWidgetScheduleManager.scheduleNext(context)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "next widget update scheduling failed", e)
                } finally {
                    pending.finish()
                }
            }
        }
    }

    companion object {
        private const val TAG = "BapUWidgetScheduledUpdate"
    }
}
