package pro.hexa.meal.meal_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 시각 호출 예약(AlarmManager)은 재부팅하면 사라진다(WorkManager 주기 작업은 자체 DB로
 * 살아남음). 위젯이 하나라도 있으면 부팅 직후 다음 호출을 다시 예약해준다.
 */
class BapUWidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (BapUWidgetUpdateWorker.hasAnyWidget(context)) {
            BapUWidgetScheduleManager.scheduleNext(context)
        }
    }
}
