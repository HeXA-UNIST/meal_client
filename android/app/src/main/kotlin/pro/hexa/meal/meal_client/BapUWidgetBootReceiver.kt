package pro.hexa.meal.meal_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 시각 호출 예약(AlarmManager)은 재부팅하면 사라진다.
 * 위젯이 하나라도 있으면 부팅 직후 cache-only로 현재 화면을 복구한 뒤 다음 호출을 예약한다.
 */
class BapUWidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val pending = goAsync()
        BapUWidgetUpdateDispatcher.execute {
            try {
                if (BapUWidgetUpdateDispatcher.hasAnyWidget(context)) {
                    BapUWidgetUpdateDispatcher.renderAllWidgetsLenient(context)
                    BapUWidgetScheduleManager.scheduleNext(context)
                }
            } catch (e: Exception) {
                Log.e(TAG, "boot widget restore failed", e)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private const val TAG = "BapUWidgetBootReceiver"
    }
}
