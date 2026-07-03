package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView

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
            val cafeteriaName = context.getString(cafeteriaNameResId(cafeteria))
            val mealLabel = context.getString(mealOfDayResId(mealOfDay))

            views.setTextViewText(R.id.tv_cafeteria_name, cafeteriaName)
            views.setTextViewText(R.id.tv_meal_of_day, mealLabel)
            views.bindFoodType(context, R.id.tv_food_type, cafeteria)

            val widthDp  = widgetWidthDp(manager, widgetId)
            val heightDp = widgetHeightDp(manager, widgetId)
            val menuSp   = calcMenuTextSp(widthDp, columns = 1)
            val statusSp = calcStatusTextSp(menuSp)
            val widthPx  = safeMeasureSizePx(dpToPx(context, widthDp.toFloat()).toInt())
            val heightPx = safeMeasureSizePx(dpToPx(context, heightDp.toFloat()).toInt())

            val (statusColor, statusText) = operatingStatusDisplay(context, cafeteria, mealOfDay)

            fun setup(root: View) {
                root.findViewById<TextView>(R.id.tv_cafeteria_name).apply {
                    text = cafeteriaName
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(R.id.tv_meal_of_day).apply {
                    text = mealLabel
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(R.id.tv_food_type).apply {
                    val foodTypeResId = cafeteriaFoodTypeResId(cafeteria)
                    visibility = if (foodTypeResId != null) View.VISIBLE else View.GONE
                    if (foodTypeResId != null) text = context.getString(foodTypeResId)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(R.id.tv_status).apply {
                    text = statusText
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, statusSp)
                }
                root.findViewById<TextView>(R.id.tv_menu_left).setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                root.findViewById<TextView>(R.id.tv_menu_right).setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
            }

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            val (left, right) = splitMenuTwoColumnsByRealLayout(
                context, R.layout.widget_4x2_status, R.id.tv_menu_left, R.id.tv_menu_right,
                widthPx, heightPx, items, ::setup
            )
            views.setTextViewText(R.id.tv_menu_left, left)
            views.setTextViewText(R.id.tv_menu_right, right)
            views.setInt(R.id.tv_menu_left, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)
            views.setInt(R.id.tv_menu_right, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)

            views.setTextViewText(R.id.tv_status, statusText)
            views.setTextColor(R.id.tv_status, statusColor)

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
