package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import android.widget.RemoteViews

class BapUWidget4x2StatusProvider : BapUBaseWidgetProvider() {

    override val TAG = Companion.TAG

    override fun performUpdate(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) =
        Companion.updateWidget(context, manager, widgetId, data)

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) clearWidgetConfig(context, id)
    }

    companion object {
        const val TAG = "BapUWidget4x2Status"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId")
            val views = RemoteViews(context.packageName, R.layout.widget_4x2_status)
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
            val panelH       = heightDp - 28
            val maxLines     = calcMaxMenuLines(panelH, menuSp, fontScale)
            val colWidthDp   = (panelWidthDp - 16) / 2
            val charsPerLine = calcCharsPerLine(colWidthDp, menuSp, fontScale)

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            val (left, right) = splitMenuTwoColumns(items, maxLines, charsPerLine)
            views.setTextViewText(R.id.tv_menu_left, left)
            views.setTextViewText(R.id.tv_menu_right, right)
            views.setInt(R.id.tv_menu_left, "setMaxLines", maxLines)
            views.setInt(R.id.tv_menu_right, "setMaxLines", maxLines)

            views.applyOperatingStatus(context, R.id.tv_status, cafeteria, mealOfDay)

            views.applyTextSizes(
                menuSp, listOf(R.id.tv_menu_left, R.id.tv_menu_right),
                statusSp, listOf(R.id.tv_status),
                headerIds = listOf(R.id.tv_cafeteria_name, R.id.tv_food_type, R.id.tv_meal_of_day)
            )
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))

            manager.updateAppWidget(widgetId, views)
        }
    }
}
