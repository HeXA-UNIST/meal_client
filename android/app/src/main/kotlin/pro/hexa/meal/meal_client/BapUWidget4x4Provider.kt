package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews

class BapUWidget4x4Provider : AppWidgetProvider() {

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

    override fun onDisabled(context: Context) {
        if (!BapUWidgetUpdateWorker.hasAnyWidget(context)) BapUWidgetUpdateWorker.cancel(context)
    }

    companion object {
        private const val TAG = "BapUWidget4x4"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData?) {
            Log.d(TAG, "updateWidget id=$widgetId")
            val views = RemoteViews(context.packageName, R.layout.widget_4x4)
            val mealOfDay = data?.mealOfDay ?: currentMealOfDay()
            val mealLabel = context.getString(mealOfDayResId(mealOfDay))

            // 기기별 크기 계산 (좌우 2패널 × 상하 2행)
            val widthDp   = widgetWidthDp(manager, widgetId)
            val heightDp  = widgetHeightDp(manager, widgetId)
            val menuSp    = calcMenuTextSp(widthDp, columns = 2)
            val kcalSp    = calcKcalTextSp(menuSp)
            // 4×4는 상하 2행: 패널 높이 = (전체 - 패딩28 - 행간갭24) / 2
            val panelH    = (heightDp - 28 - 24) / 2
            val maxLines  = calcMaxMenuLines(panelH, menuSp)

            views.setTextViewText(R.id.tv_name_dorm_korean, context.getString(R.string.cafeteria_dormitory))
            views.setTextViewText(R.id.tv_meal_dorm_korean, mealLabel)
            views.setTextViewText(R.id.tv_menu_dorm_korean, truncateMenu(data?.dormKoreanMenu ?: emptyList(), maxLines))
            views.setTextViewText(R.id.tv_kcal_dorm_korean,
                if (data?.dormKoreanKcal != null) context.getString(R.string.widget_kcal, data.dormKoreanKcal) else "")

            views.setTextViewText(R.id.tv_name_dorm_halal, context.getString(R.string.cafeteria_dormitory))
            views.setTextViewText(R.id.tv_meal_dorm_halal, mealLabel)
            views.setTextViewText(R.id.tv_menu_dorm_halal, truncateMenu(data?.dormHalalMenu ?: emptyList(), maxLines))
            views.setTextViewText(R.id.tv_kcal_dorm_halal,
                if (data?.dormHalalKcal != null) context.getString(R.string.widget_kcal, data.dormHalalKcal) else "")

            views.setTextViewText(R.id.tv_name_student, context.getString(R.string.cafeteria_student))
            views.setTextViewText(R.id.tv_meal_student, mealLabel)
            views.setTextViewText(R.id.tv_menu_student, truncateMenu(data?.studentMenu ?: emptyList(), maxLines))
            views.setTextViewText(R.id.tv_kcal_student,
                if (data?.studentKcal != null) context.getString(R.string.widget_kcal, data.studentKcal) else "")

            views.setTextViewText(R.id.tv_name_faculty, context.getString(R.string.cafeteria_faculty))
            views.setTextViewText(R.id.tv_meal_faculty, mealLabel)
            views.setTextViewText(R.id.tv_menu_faculty, truncateMenu(data?.facultyMenu ?: emptyList(), maxLines))
            views.setTextViewText(R.id.tv_kcal_faculty,
                if (data?.facultyKcal != null) context.getString(R.string.widget_kcal, data.facultyKcal) else "")

            val menuIds = listOf(
                R.id.tv_menu_dorm_korean, R.id.tv_menu_dorm_halal,
                R.id.tv_menu_student,     R.id.tv_menu_faculty
            )
            for (id in menuIds) views.setInt(id, "setMaxLines", maxLines)

            views.applyTextSizes(
                menuSp, menuIds,
                kcalSp, listOf(
                    R.id.tv_kcal_dorm_korean, R.id.tv_kcal_dorm_halal,
                    R.id.tv_kcal_student,     R.id.tv_kcal_faculty
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
    }
}
