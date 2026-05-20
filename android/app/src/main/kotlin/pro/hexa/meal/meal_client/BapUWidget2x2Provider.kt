package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews

class BapUWidget2x2Provider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d(TAG, "onUpdate ids=${appWidgetIds.toList()}")
        val pending = goAsync()
        Thread {
            try {
                val data = BapUWidgetFetcher.fetch()
                for (id in appWidgetIds) {
                    try { updateWidget(context, appWidgetManager, id, data) }
                    catch (e: Exception) { Log.e(TAG, "update failed id=$id", e) }
                }
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
                val data = BapUWidgetFetcher.fetch()
                updateWidget(context, appWidgetManager, appWidgetId, data)
            } finally {
                pending.finish()
            }
        }.start()
    }

    override fun onEnabled(context: Context) {
        BapUWidgetUpdateWorker.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) clearWidgetConfig(context, id)
    }

    override fun onDisabled(context: Context) {
        if (!BapUWidgetUpdateWorker.hasAnyWidget(context)) BapUWidgetUpdateWorker.cancel(context)
    }

    companion object {
        private const val TAG = "BapUWidget2x2"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId data=$data")
            val views = RemoteViews(context.packageName, R.layout.widget_2x2)
            val mealOfDay = data?.mealOfDay ?: currentMealOfDay()
            val cafeteria = loadSingleCafeteria(context, widgetId)

            views.setTextViewText(R.id.tv_cafeteria_name, context.getString(cafeteriaNameResId(cafeteria)))
            views.setTextViewText(R.id.tv_meal_of_day, context.getString(mealOfDayResId(mealOfDay)))
            views.bindFoodType(context, R.id.tv_food_type, cafeteria)

            // 기기별 크기에 맞게 텍스트 크기와 최대 줄 수 계산
            val widthDp  = widgetWidthDp(manager, widgetId)
            val heightDp = widgetHeightDp(manager, widgetId)
            val menuSp   = calcMenuTextSp(widthDp, columns = 1)
            val kcalSp   = calcKcalTextSp(menuSp)
            val maxLines = calcMaxMenuLines(panelHeightDp = heightDp - 28, menuSp)

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            views.setTextViewText(R.id.tv_menu, truncateMenu(items, maxLines))
            views.setInt(R.id.tv_menu, "setMaxLines", maxLines)

            val kcal = if (data != null) kcalFromData(data, cafeteria) else null
            views.setTextViewText(R.id.tv_kcal,
                if (kcal != null) context.getString(R.string.widget_kcal, kcal) else "")

            views.applyTextSizes(
                menuSp, listOf(R.id.tv_menu),
                kcalSp,  listOf(R.id.tv_kcal),
                headerIds = listOf(R.id.tv_cafeteria_name, R.id.tv_food_type, R.id.tv_meal_of_day)
            )
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))

            manager.updateAppWidget(widgetId, views)
        }
    }
}
