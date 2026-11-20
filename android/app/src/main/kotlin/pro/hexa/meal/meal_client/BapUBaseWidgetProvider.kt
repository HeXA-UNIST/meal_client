package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetPlugin

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
        data: WidgetMealData,
        skipUnchanged: Boolean = false,
    )

    override fun onReceive(context: Context, intent: Intent) {
        // 런처의 갱신 요청은 항상 다시 그린다. Flutter가 반복 요청한 경우만 생략한다.
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE &&
            intent.getBooleanExtra(HomeWidgetPlugin.TRIGGERED_FROM_HOME_WIDGET, false)) {
            updateWidgets(
                context, AppWidgetManager.getInstance(context),
                intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS) ?: return,
                skipUnchanged = true,
            )
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) = updateWidgets(context, appWidgetManager, appWidgetIds, skipUnchanged = false)

    private fun updateWidgets(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        skipUnchanged: Boolean,
    ) {
        if (appWidgetIds.isEmpty()) return
        enqueueBroadcastWork {
            try {
                BapUWidgetUpdateDispatcher.renderWidgetIds(context, appWidgetManager, appWidgetIds) { id, data ->
                    performUpdate(context, appWidgetManager, id, data, skipUnchanged)
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
            BapUMealBackgroundRefresh.sync(context)
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
        enqueueBroadcastWork {
            BapUMealBackgroundRefresh.sync(context)
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
