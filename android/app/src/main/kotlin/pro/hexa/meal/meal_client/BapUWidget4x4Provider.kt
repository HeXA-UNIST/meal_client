package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView

class BapUWidget4x4Provider : BapUBaseWidgetProvider() {

    override val TAG = Companion.TAG

    override fun performUpdate(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) =
        Companion.updateWidget(context, manager, widgetId, data)

    // 4x4는 식당별 설정이 없으므로 onDeleted 불필요

    companion object {
        const val TAG = "BapUWidget4x4"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId")
            val views = RemoteViews(context.packageName, R.layout.widget_4x4)
            val mealOfDay = data?.mealOfDay ?: currentMealOfDay()
            val mealLabel = context.getString(mealOfDayResId(mealOfDay))

            val widthDp  = widgetWidthDp(manager, widgetId)
            val heightDp = widgetHeightDp(manager, widgetId)
            val menuSp   = calcMenuTextSp(widthDp, columns = 2)
            val statusSp = calcStatusTextSp(menuSp)
            val widthPx  = safeMeasureSizePx(dpToPx(context, widthDp.toFloat()).toInt())
            val heightPx = safeMeasureSizePx(dpToPx(context, heightDp.toFloat()).toInt())

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_DORM_KOREAN, widthPx, heightPx, menuSp, statusSp,
                tvName = R.id.tv_name_dorm_korean, tvMeal = R.id.tv_meal_dorm_korean,
                tvMenu = R.id.tv_menu_dorm_korean, tvStatus = R.id.tv_status_dorm_korean)

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_DORM_HALAL, widthPx, heightPx, menuSp, statusSp,
                tvName = R.id.tv_name_dorm_halal, tvMeal = R.id.tv_meal_dorm_halal,
                tvMenu = R.id.tv_menu_dorm_halal, tvStatus = R.id.tv_status_dorm_halal)

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_STUDENT, widthPx, heightPx, menuSp, statusSp,
                tvName = R.id.tv_name_student, tvMeal = R.id.tv_meal_student,
                tvMenu = R.id.tv_menu_student, tvStatus = R.id.tv_status_student)

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_FACULTY, widthPx, heightPx, menuSp, statusSp,
                tvName = R.id.tv_name_faculty, tvMeal = R.id.tv_meal_faculty,
                tvMenu = R.id.tv_menu_faculty, tvStatus = R.id.tv_status_faculty)

            val menuIds = listOf(
                R.id.tv_menu_dorm_korean, R.id.tv_menu_dorm_halal,
                R.id.tv_menu_student,     R.id.tv_menu_faculty
            )
            for (id in menuIds) views.setInt(id, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)

            views.applyTextSizes(
                menuSp, menuIds,
                statusSp, listOf(
                    R.id.tv_status_dorm_korean, R.id.tv_status_dorm_halal,
                    R.id.tv_status_student,     R.id.tv_status_faculty
                ),
                headerIds = listOf(
                    R.id.tv_name_dorm_korean, R.id.tv_food_type_dorm_korean, R.id.tv_meal_dorm_korean,
                    R.id.tv_name_dorm_halal,  R.id.tv_food_type_dorm_halal,  R.id.tv_meal_dorm_halal,
                    R.id.tv_name_student,     R.id.tv_meal_student,
                    R.id.tv_name_faculty,     R.id.tv_meal_faculty
                )
            )
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))

            manager.updateAppWidget(widgetId, views)
        }

        private fun bindPanel(
            context: Context,
            views: RemoteViews,
            data: WidgetMealData?,
            mealLabel: String,
            mealOfDay: Int,
            cafeteria: Int,
            widthPx: Int,
            heightPx: Int,
            menuSp: Float,
            statusSp: Float,
            tvName: Int, tvMeal: Int, tvMenu: Int, tvStatus: Int
        ) {
            val cafeteriaName = context.getString(cafeteriaNameResId(cafeteria))
            views.setTextViewText(tvName, cafeteriaName)
            views.setTextViewText(tvMeal, mealLabel)

            val (statusColor, statusText) = operatingStatusDisplay(context, cafeteria, mealOfDay)

            fun setup(root: View) {
                root.findViewById<TextView>(tvName).apply {
                    text = cafeteriaName
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(tvMeal).apply {
                    text = mealLabel
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(tvStatus).apply {
                    text = statusText
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, statusSp)
                }
            }

            val items = if (data != null) menuFromData(data, cafeteria) else emptyList()
            val menuText = truncateMenuByRealLayout(
                context, R.layout.widget_4x4, tvMenu, widthPx, heightPx, items, ::setup
            )
            views.setTextViewText(tvMenu, menuText)

            views.setTextViewText(tvStatus, statusText)
            views.setTextColor(tvStatus, statusColor)
        }
    }
}
