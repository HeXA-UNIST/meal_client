package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import android.widget.RemoteViews

class BapUWidget4x2DualProvider : BapUBaseWidgetProvider() {

    override val TAG = Companion.TAG

    override fun performUpdate(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) =
        Companion.updateWidget(context, manager, widgetId, data)

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) clearWidgetConfig(context, id)
    }

    companion object {
        const val TAG = "BapUWidget4x2Dual"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId")
            val views = RemoteViews(context.packageName, R.layout.widget_4x2_dual)
            val mealOfDay = data?.mealOfDay ?: currentMealOfDay()
            val (c0, c1) = loadDualCafeterias(context, widgetId)

            val widthDp      = widgetWidthDp(manager, widgetId)
            val heightDp     = widgetHeightDp(manager, widgetId)
            val panelWidthDp = calcPanelWidthDp(widthDp, columns = 2)
            val menuSp       = calcMenuTextSp(widthDp, columns = 2)
            val statusSp     = calcStatusTextSp(menuSp)
            val fontScale    = context.resources.configuration.fontScale
            val maxLines     = calcMaxMenuLines(panelHeightDp = heightDp - 28, menuSp, fontScale)
            val charsPerLine = calcCharsPerLine(panelWidthDp, menuSp, fontScale)

            bindPanel(context, views, data, mealOfDay, c0, maxLines, charsPerLine,
                tvName = R.id.tv_cafeteria_name_0,
                tvMeal = R.id.tv_meal_of_day_0,
                tvFoodType = R.id.tv_food_type_0,
                tvMenu = R.id.tv_menu_0,
                tvStatus = R.id.tv_status_0)

            bindPanel(context, views, data, mealOfDay, c1, maxLines, charsPerLine,
                tvName = R.id.tv_cafeteria_name_1,
                tvMeal = R.id.tv_meal_of_day_1,
                tvFoodType = R.id.tv_food_type_1,
                tvMenu = R.id.tv_menu_1,
                tvStatus = R.id.tv_status_1)

            views.applyTextSizes(
                menuSp, listOf(R.id.tv_menu_0, R.id.tv_menu_1),
                statusSp, listOf(R.id.tv_status_0, R.id.tv_status_1),
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
            charsPerLine: Int,
            tvName: Int, tvMeal: Int, tvFoodType: Int, tvMenu: Int, tvStatus: Int
        ) {
            views.setTextViewText(tvName, context.getString(cafeteriaNameResId(cafeteria)))
            views.setTextViewText(tvMeal, context.getString(mealOfDayResId(mealOfDay)))
            views.bindFoodType(context, tvFoodType, cafeteria)

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            views.setTextViewText(tvMenu, truncateMenu(items, maxLines, charsPerLine))
            views.setInt(tvMenu, "setMaxLines", maxLines)

            views.applyOperatingStatus(context, tvStatus, cafeteria, mealOfDay)
        }
    }
}
