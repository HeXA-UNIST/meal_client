package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle

/**
 * 모든 BapU 위젯 provider의 공통 보일러플레이트를 담당한다.
 * 서브클래스는 [TAG]와 [performUpdate]만 구현하면 된다.
 */
abstract class BapUBaseWidgetProvider : AppWidgetProvider() {

    protected abstract val TAG: String

    /** Worker/Config Activity에서 정적으로 호출하는 companion.updateWidget을 인스턴스 레벨로 위임. */
    protected abstract fun performUpdate(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: WidgetMealData?
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val pending = goAsync()
        Thread {
            try {
                BapUWidgetUpdateDispatcher.renderWidgetIds(context, appWidgetManager, appWidgetIds) { id, data ->
                    performUpdate(context, appWidgetManager, id, data)
                }
                // onEnabled는 위젯이 처음 추가될 때만 불리므로, 앱 업데이트로 재설치된 경우
                // 기존 위젯의 예약 호출 체인이 안 걸려있을 수 있다. 여기서도 매번 보정해준다.
                BapUWidgetScheduleManager.scheduleNext(context)
            } finally {
                pending.finish()
            }
        }.start()
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        val pending = goAsync()
        Thread {
            try {
                BapUWidgetUpdateDispatcher.renderWidgetIds(context, appWidgetManager, intArrayOf(appWidgetId)) { id, data ->
                    performUpdate(context, appWidgetManager, id, data)
                }
            } finally {
                pending.finish()
            }
        }.start()
    }

    override fun onEnabled(context: Context) {
        BapUWidgetUpdateDispatcher.renderAllWidgets(context)
        BapUWidgetScheduleManager.scheduleNext(context)
    }

    override fun onDisabled(context: Context) {
        if (!BapUWidgetUpdateDispatcher.hasAnyWidget(context)) {
            BapUWidgetUpdateWorker.cancelLegacy(context)
            BapUWidgetScheduleManager.cancel(context)
        }
    }
}
