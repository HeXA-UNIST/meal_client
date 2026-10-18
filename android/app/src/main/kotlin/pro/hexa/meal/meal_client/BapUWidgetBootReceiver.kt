package pro.hexa.meal.meal_client

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 재부팅 또는 앱 업데이트 뒤 기존 위젯을 캐시로 다시 그리고 다음 호출을 예약한다.
 */
class BapUWidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pending = goAsync()
        BapUWidgetUpdateDispatcher.execute {
            try {
                if (BapUWidgetUpdateDispatcher.hasAnyWidget(context)) {
                    BapUWidgetUpdateDispatcher.renderAllWidgetsLenient(context)
                    BapUWidgetScheduleManager.scheduleNext(context)
                }
            } catch (e: Exception) {
                logWidgetFailure("restore", e)
            } finally {
                pending.finish()
            }
        }
    }
}
