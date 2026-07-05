package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView

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

            val widthDp  = widgetWidthDp(manager, widgetId)
            val heightDp = widgetHeightDp(manager, widgetId)
            val menuSp   = calcMenuTextSp(widthDp, columns = 2)
            val statusSp = calcStatusTextSp(menuSp)
            val widthPx  = safeMeasureSizePx(dpToPx(context, widthDp.toFloat()).toInt())
            val heightPx = safeMeasureSizePx(dpToPx(context, heightDp.toFloat()).toInt())

            bindPanel(context, views, data, mealOfDay, c0, widthPx, heightPx, menuSp, statusSp,
                tvName = R.id.tv_cafeteria_name_0,
                tvMeal = R.id.tv_meal_of_day_0,
                tvFoodType = R.id.tv_food_type_0,
                tvMenu = R.id.tv_menu_0,
                tvStatus = R.id.tv_status_0)

            bindPanel(context, views, data, mealOfDay, c1, widthPx, heightPx, menuSp, statusSp,
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
            widthPx: Int,
            heightPx: Int,
            menuSp: Float,
            statusSp: Float,
            tvName: Int, tvMeal: Int, tvFoodType: Int, tvMenu: Int, tvStatus: Int
        ) {
            val cafeteriaName = context.getString(cafeteriaNameResId(cafeteria))
            val mealLabel = context.getString(mealOfDayResId(mealOfDay))
            views.setTextViewText(tvName, cafeteriaName)
            views.setTextViewText(tvMeal, mealLabel)
            views.bindFoodType(context, tvFoodType, cafeteria)

            val statusDisplay = operatingStatusDisplay(context, cafeteria, mealOfDay)

            fun setup(root: View) {
                root.findViewById<TextView>(tvName).apply {
                    text = cafeteriaName
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(tvMeal).apply {
                    text = mealLabel
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(tvFoodType).apply {
                    val foodTypeResId = cafeteriaFoodTypeResId(cafeteria)
                    visibility = if (foodTypeResId != null) View.VISIBLE else View.GONE
                    if (foodTypeResId != null) text = context.getString(foodTypeResId)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(tvStatus).bindOperatingStatusForMeasure(statusDisplay, statusSp)
            }

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            val menuText = truncateMenuByRealLayout(
                context, R.layout.widget_4x2_dual, tvMenu, widthPx, heightPx, items, ::setup
            )
            views.setTextViewText(tvMenu, menuText)
            views.setInt(tvMenu, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)

            views.bindOperatingStatus(tvStatus, statusDisplay)
        }
    }
}
