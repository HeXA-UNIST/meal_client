package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import android.widget.RemoteViews

class BapUWidget2x2Provider : BapUBaseWidgetProvider() {

    override val TAG = Companion.TAG

    override fun performUpdate(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) =
        Companion.updateWidget(context, manager, widgetId, data)

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) clearWidgetConfig(context, id)
    }

    companion object {
        const val TAG = "BapUWidget2x2"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId data=$data")
            val views = RemoteViews(context.packageName, R.layout.widget_2x2)
            val mealOfDay = data?.mealOfDay ?: currentMealOfDay()
            val cafeteria = loadSingleCafeteria(context, widgetId)

            views.setTextViewText(R.id.tv_cafeteria_name, context.getString(cafeteriaNameResId(cafeteria)))
            views.setTextViewText(R.id.tv_meal_of_day, context.getString(mealOfDayResId(mealOfDay)))
            views.bindFoodType(context, R.id.tv_food_type, cafeteria)

            val widthDp      = widgetWidthDp(manager, widgetId)
            val heightDp     = widgetHeightDp(manager, widgetId)
            val panelWidthDp = calcPanelWidthDp(widthDp, columns = 1)
            val menuSp       = calcMenuTextSp(widthDp, columns = 1)
            val statusSp     = calcStatusTextSp(menuSp)
            val fontScale    = context.resources.configuration.fontScale
            val maxLines     = calcMaxMenuLines(panelHeightDp = heightDp - 28, menuSp, fontScale)
            val charsPerLine = calcCharsPerLine(panelWidthDp, menuSp, fontScale)

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            views.setTextViewText(R.id.tv_menu, truncateMenu(items, maxLines, charsPerLine))
            views.setInt(R.id.tv_menu, "setMaxLines", maxLines)

            views.applyOperatingStatus(context, R.id.tv_status, cafeteria, mealOfDay)

            views.applyTextSizes(
                menuSp, listOf(R.id.tv_menu),
                statusSp, listOf(R.id.tv_status),
                headerIds = listOf(R.id.tv_cafeteria_name, R.id.tv_food_type, R.id.tv_meal_of_day)
            )
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))

            manager.updateAppWidget(widgetId, views)
        }
    }
}
