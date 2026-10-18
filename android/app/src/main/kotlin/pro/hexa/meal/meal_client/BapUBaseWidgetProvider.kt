package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle

/**
 * 모든 BapU 위젯 provider의 공통 보일러플레이트를 담당한다.
 * 서브클래스는 [performUpdate]만 구현하면 된다.
 */
abstract class BapUBaseWidgetProvider : AppWidgetProvider() {

    /** Worker/Config Activity에서 정적으로 호출하는 companion.updateWidget을 인스턴스 레벨로 위임. */
    protected abstract fun performUpdate(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        data: WidgetMealData
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        if (appWidgetIds.isEmpty()) return
        enqueueBroadcastWork {
            try {
                BapUWidgetUpdateDispatcher.renderWidgetIds(context, appWidgetManager, appWidgetIds) { id, data ->
                    performUpdate(context, appWidgetManager, id, data)
                }
            } catch (e: Exception) {
                logWidgetFailure("render", e)
            } finally {
                // home_widget과 시스템 갱신 모두 다음 경계를 보정한다. 렌더 실패 시에도
                // 예약을 시도해 캐시 복구 뒤 다시 갱신할 기회를 남긴다.
                try {
                    BapUWidgetScheduleManager.scheduleNext(context)
                } catch (e: Exception) {
                    logWidgetFailure("schedule", e)
                }
            }
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        enqueueBroadcastWork {
            try {
                BapUWidgetUpdateDispatcher.renderWidgetIds(context, appWidgetManager, intArrayOf(appWidgetId)) { id, data ->
                    performUpdate(context, appWidgetManager, id, data)
                }
            } catch (e: Exception) {
                logWidgetFailure("resize", e)
            }
        }
    }

    override fun onEnabled(context: Context) {
        enqueueBroadcastWork {
            BapUWidgetUpdateDispatcher.renderAllWidgetsLenient(context)
            try {
                BapUWidgetScheduleManager.scheduleNext(context)
            } catch (e: Exception) {
                logWidgetFailure("schedule", e)
            }
        }
    }

    override fun onDisabled(context: Context) {
        if (!BapUWidgetUpdateDispatcher.hasAnyWidget(context)) {
            BapUWidgetUpdateWorker.cancelLegacy(context)
            BapUWidgetScheduleManager.cancel(context)
        }
    }

    /** BroadcastReceiver의 수명 안에서 모든 무거운 cache/render 작업을 공용 큐로 넘긴다. */
    private fun enqueueBroadcastWork(block: () -> Unit) {
        val pending = goAsync()
        BapUWidgetUpdateDispatcher.execute {
            try {
                block()
            } finally {
                pending.finish()
            }
        }
    }
}
