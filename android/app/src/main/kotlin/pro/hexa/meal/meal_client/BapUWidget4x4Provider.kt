package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log
import android.widget.RemoteViews

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

            val widthDp      = widgetWidthDp(manager, widgetId)
            val heightDp     = widgetHeightDp(manager, widgetId)
            val panelWidthDp = calcPanelWidthDp(widthDp, columns = 2)
            val menuSp       = calcMenuTextSp(widthDp, columns = 2)
            val statusSp     = calcStatusTextSp(menuSp)
            val fontScale    = context.resources.configuration.fontScale
            // 4×4는 상하 2행: 패널 높이 = (전체 - 패딩28 - 행간갭24) / 2
            val panelH       = (heightDp - 28 - 24) / 2
            val maxLines     = calcMaxMenuLines(panelH, menuSp, fontScale)
            val charsPerLine = calcCharsPerLine(panelWidthDp, menuSp, fontScale)

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_DORM_KOREAN, maxLines, charsPerLine,
                tvName = R.id.tv_name_dorm_korean, tvMeal = R.id.tv_meal_dorm_korean,
                tvMenu = R.id.tv_menu_dorm_korean, tvStatus = R.id.tv_status_dorm_korean)

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_DORM_HALAL, maxLines, charsPerLine,
                tvName = R.id.tv_name_dorm_halal, tvMeal = R.id.tv_meal_dorm_halal,
                tvMenu = R.id.tv_menu_dorm_halal, tvStatus = R.id.tv_status_dorm_halal)

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_STUDENT, maxLines, charsPerLine,
                tvName = R.id.tv_name_student, tvMeal = R.id.tv_meal_student,
                tvMenu = R.id.tv_menu_student, tvStatus = R.id.tv_status_student)

            bindPanel(context, views, data, mealLabel, mealOfDay, CAFE_FACULTY, maxLines, charsPerLine,
                tvName = R.id.tv_name_faculty, tvMeal = R.id.tv_meal_faculty,
                tvMenu = R.id.tv_menu_faculty, tvStatus = R.id.tv_status_faculty)

            val menuIds = listOf(
                R.id.tv_menu_dorm_korean, R.id.tv_menu_dorm_halal,
                R.id.tv_menu_student,     R.id.tv_menu_faculty
            )
            for (id in menuIds) views.setInt(id, "setMaxLines", maxLines)

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
            maxLines: Int,
            charsPerLine: Int,
            tvName: Int, tvMeal: Int, tvMenu: Int, tvStatus: Int
        ) {
            views.setTextViewText(tvName, context.getString(cafeteriaNameResId(cafeteria)))
            views.setTextViewText(tvMeal, mealLabel)
            views.setTextViewText(tvMenu,
                truncateMenu(if (data != null) menuFromData(data, cafeteria) else emptyList(), maxLines, charsPerLine))
            views.applyOperatingStatus(context, tvStatus, cafeteria, mealOfDay)
        }
    }
}
