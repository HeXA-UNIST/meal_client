package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews

class BapUWidget4x2DualProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d(TAG, "onUpdate ids=${appWidgetIds.toList()}")
        val pending = goAsync()
        Thread {
            try {
                val data = BapUWidgetFetcher.fetch(context)
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
                val data = BapUWidgetFetcher.fetch(context)
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
        private const val TAG = "BapUWidget4x2Dual"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId")
            val views = RemoteViews(context.packageName, R.layout.widget_4x2_dual)
            val mealOfDay = data?.mealOfDay ?: currentMealOfDay()
            val (c0, c1) = loadDualCafeterias(context, widgetId)

            // 기기별 크기 계산 (좌우 2패널)
            val widthDp  = widgetWidthDp(manager, widgetId)
            val heightDp = widgetHeightDp(manager, widgetId)
            val menuSp   = calcMenuTextSp(widthDp, columns = 2)
            val kcalSp   = calcKcalTextSp(menuSp)
            val maxLines = calcMaxMenuLines(panelHeightDp = heightDp - 28, menuSp)

            bindPanel(context, views, data, mealOfDay, c0, maxLines,
                tvName = R.id.tv_cafeteria_name_0,
                tvMeal = R.id.tv_meal_of_day_0,
                tvFoodType = R.id.tv_food_type_0,
                tvMenu = R.id.tv_menu_0,
                tvKcal = R.id.tv_kcal_0)

            bindPanel(context, views, data, mealOfDay, c1, maxLines,
                tvName = R.id.tv_cafeteria_name_1,
                tvMeal = R.id.tv_meal_of_day_1,
                tvFoodType = R.id.tv_food_type_1,
                tvMenu = R.id.tv_menu_1,
                tvKcal = R.id.tv_kcal_1)

            views.applyTextSizes(
                menuSp, listOf(R.id.tv_menu_0, R.id.tv_menu_1),
                kcalSp,  listOf(R.id.tv_kcal_0, R.id.tv_kcal_1),
                headerIds = listOf(
                    R.id.tv_cafeteria_name_0, R.id.tv_food_type_0, R.id.tv_meal_of_day_0,
                    R.id.tv_cafeteria_name_1, R.id.tv_food_type_1, R.id.tv_meal_of_day_1
                )
            )
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))

            manager.updateAppWidget(widgetId, views)
        }

        private fun bindPanel(
            context: Context,
            views: RemoteViews,
            data: WidgetMealData?,
            mealOfDay: Int,
            cafeteria: Int,
            maxLines: Int,
            tvName: Int, tvMeal: Int, tvFoodType: Int, tvMenu: Int, tvKcal: Int
        ) {
            views.setTextViewText(tvName, context.getString(cafeteriaNameResId(cafeteria)))
            views.setTextViewText(tvMeal, context.getString(mealOfDayResId(mealOfDay)))
            views.bindFoodType(context, tvFoodType, cafeteria)

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            views.setTextViewText(tvMenu, truncateMenu(items, maxLines))
            views.setInt(tvMenu, "setMaxLines", maxLines)

            val kcal = if (data != null) kcalFromData(data, cafeteria) else null
            views.setTextViewText(tvKcal,
                if (kcal != null) context.getString(R.string.widget_kcal, kcal) else "")
        }
    }
}
