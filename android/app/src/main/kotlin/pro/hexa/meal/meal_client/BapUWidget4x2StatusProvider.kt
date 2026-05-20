package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews

class BapUWidget4x2StatusProvider : AppWidgetProvider() {

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
        private const val TAG = "BapUWidget4x2Status"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId")
            val views = RemoteViews(context.packageName, R.layout.widget_4x2_status)
            val mealOfDay = data?.mealOfDay ?: currentMealOfDay()
            val cafeteria = loadSingleCafeteria(context, widgetId)

            views.setTextViewText(R.id.tv_cafeteria_name, context.getString(cafeteriaNameResId(cafeteria)))
            views.setTextViewText(R.id.tv_meal_of_day, context.getString(mealOfDayResId(mealOfDay)))
            views.bindFoodType(context, R.id.tv_food_type, cafeteria)

            val result = getOperatingStatus(cafeteria, mealOfDay)
            applyOperatingStatus(context, views, result)

            // 기기별 크기 계산 (단일 패널, 메뉴 2열)
            // kcal과 status는 한 행에 나란히 표시되므로 calcMaxMenuLines가 그대로 적용된다.
            val widthDp  = widgetWidthDp(manager, widgetId)
            val heightDp = widgetHeightDp(manager, widgetId)
            val menuSp   = calcMenuTextSp(widthDp, columns = 1)
            val kcalSp   = calcKcalTextSp(menuSp)
            val panelH   = heightDp - 28
            val maxLines = calcMaxMenuLines(panelH, menuSp)

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            val (left, right) = splitMenuTwoColumns(items, maxLines)
            views.setTextViewText(R.id.tv_menu_left, left)
            views.setTextViewText(R.id.tv_menu_right, right)
            views.setInt(R.id.tv_menu_left, "setMaxLines", maxLines)
            views.setInt(R.id.tv_menu_right, "setMaxLines", maxLines)

            val kcal = if (data != null) kcalFromData(data, cafeteria) else null
            views.setTextViewText(R.id.tv_kcal,
                if (kcal != null) context.getString(R.string.widget_kcal, kcal) else "")

            views.applyTextSizes(
                menuSp, listOf(R.id.tv_menu_left, R.id.tv_menu_right),
                kcalSp,  listOf(R.id.tv_kcal),
                headerIds = listOf(R.id.tv_cafeteria_name, R.id.tv_food_type, R.id.tv_meal_of_day)
            )
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))

            manager.updateAppWidget(widgetId, views)
        }

        private fun applyOperatingStatus(context: Context, views: RemoteViews, result: OperatingResult) {
            val (textColor, statusText) = when (result.status) {
                OperatingStatus.BEFORE_OPEN -> Pair(
                    context.getColor(R.color.widget_status_before),
                    context.getString(R.string.status_before_open)
                )
                OperatingStatus.OPEN -> Pair(
                    context.getColor(R.color.widget_status_open),
                    context.getString(R.string.status_open)
                )
                OperatingStatus.CLOSING_SOON -> Pair(
                    context.getColor(R.color.widget_status_closing),
                    context.getString(R.string.status_closing_soon, result.minutesLeft)
                )
                OperatingStatus.JUST_CLOSED -> Pair(
                    context.getColor(R.color.widget_status_closed),
                    context.getString(R.string.status_just_closed)
                )
            }
            views.setTextViewText(R.id.tv_status, statusText)
            views.setTextColor(R.id.tv_status, textColor)
        }
    }
}
