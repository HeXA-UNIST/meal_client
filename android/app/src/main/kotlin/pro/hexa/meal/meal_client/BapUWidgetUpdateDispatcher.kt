package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.annotation.Keep

/**
 * 위젯 렌더의 공통 진입점이다. 데이터 갱신은 Dart cache writer가 맡고, native는 cache-only로
 * 다시 그린다. 순수 native 주기 안전망이 필요해지면 provider XML의 updatePeriodMillis
 * (최소 30분, coarse하지만 권한/코드 부담이 작음)를 후속 검토 후보로 쓸 수 있다.
 */
@Keep
object BapUWidgetUpdateDispatcher {
    private const val TAG = "BapUWidgetUpdateDispatcher"

    @Keep
    fun renderAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val data = BapUWidgetFetcher.fetch(context)

        updateAll(context, manager, BapUWidget2x2Provider::class.java) {
            BapUWidget2x2Provider.updateWidget(context, manager, it, data)
        }
        updateAll(context, manager, BapUWidget4x2DualProvider::class.java) {
            BapUWidget4x2DualProvider.updateWidget(context, manager, it, data)
        }
        updateAll(context, manager, BapUWidget4x2StatusProvider::class.java) {
            BapUWidget4x2StatusProvider.updateWidget(context, manager, it, data)
        }
        updateAll(context, manager, BapUWidget4x4Provider::class.java) {
            BapUWidget4x4Provider.updateWidget(context, manager, it, data)
        }
    }

    fun renderWidgetIds(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
        update: (Int, WidgetMealData) -> Unit
    ) {
        val data = BapUWidgetFetcher.fetch(context)
        for (id in widgetIds) {
            try {
                update(id, data)
            } catch (e: Exception) {
                Log.e(TAG, "update failed id=$id", e)
            }
        }
    }

    fun hasAnyWidget(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return listOf(
            BapUWidget2x2Provider::class.java,
            BapUWidget4x2DualProvider::class.java,
            BapUWidget4x2StatusProvider::class.java,
            BapUWidget4x4Provider::class.java
        ).any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    private fun updateAll(
        context: Context,
        manager: AppWidgetManager,
        providerClass: Class<*>,
        update: (Int) -> Unit
    ) {
        for (id in manager.getAppWidgetIds(ComponentName(context, providerClass))) {
            try {
                update(id)
            } catch (e: Exception) {
                Log.e(TAG, "update failed id=$id", e)
            }
        }
    }
}
