package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView

class BapUWidget2x2Provider : BapUBaseWidgetProvider() {
    override fun performUpdate(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData, skipUnchanged: Boolean) =
        Companion.updateWidget(context, manager, widgetId, data, skipUnchanged)

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            clearWidgetConfig(context, id)
            // 렌더 큐와 같은 순서로 정리해 삭제된 ID의 기록이 남지 않게 한다.
            BapUWidgetUpdateDispatcher.execute { renderCache.remove(id) }
        }
        // 일부 위젯만 지운 경우도 남은 식당에 맞춰 다음 경계를 다시 계산한다.
        val pending = goAsync()
        BapUWidgetUpdateDispatcher.execute {
            try {
                BapUWidgetScheduleManager.scheduleNext(context)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val TAG = "BapUWidget2x2"
        private val renderCache = BapUWidgetRenderCache()

        @Suppress("DEPRECATION")
        fun updateWidget(baseContext: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData, skipUnchanged: Boolean = false) {
            // 메뉴와 라벨이 한 번 읽은 같은 언어를 사용한다.
            val context = BapUWidgetMealRepository.localizedContext(
                baseContext, requireNotNull(data.languageCode)
            )
            val options = manager.getAppWidgetOptions(widgetId)
            val cafeteria = loadSingleCafeteria(context, widgetId)
            val allowed = BapUWidgetScheduleManager.canScheduleExactAlarms(context)
            val sizes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                    ?.filter { it.width > 0f && it.height > 0f }?.distinct().orEmpty()
            } else emptyList()
            val fallbackSizes = listOf(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).toFloat() to
                    options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).toFloat(),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH).toFloat() to
                    options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT).toFloat(),
            )
            val inputs = WidgetRenderInputs(
                data, cafeteria,
                if (sizes.isEmpty()) fallbackSizes else sizes.map { it.width to it.height },
                context.resources.configuration.toString(), allowed,
            )
            renderCache.update(widgetId, inputs, skipUnchanged) {
                renderWidget(context, manager, widgetId, data, cafeteria, allowed, options, sizes)
            }
        }

        private fun renderWidget(
            context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData,
            cafeteria: Int, allowed: Boolean, options: Bundle, sizes: List<SizeF>,
        ) {
            Log.d(TAG, "updateWidget id=$widgetId data=$data")
            if (!allowed) {
                val settingsIntent = Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:${context.packageName}"),
                )
                val settingsPendingIntent = PendingIntent.getActivity(
                    context, 5101, settingsIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                val notice = RemoteViews(context.packageName, R.layout.widget_exact_alarm_notice)
                notice.setTextViewText(
                    R.id.tv_exact_alarm_notice_body,
                    context.getString(R.string.widget_exact_alarm_notice_body),
                )
                notice.setTextViewText(
                    R.id.tv_exact_alarm_notice_action,
                    context.getString(R.string.widget_exact_alarm_notice_action),
                )
                notice.setOnClickPendingIntent(R.id.widget_root, settingsPendingIntent)
                manager.updateAppWidget(widgetId, notice)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (sizes.isNotEmpty()) {
                    Log.d(TAG, "using size-specific RemoteViews: $sizes")
                    val sizeViews = sizes.associateWith { size ->
                        createRemoteViews(context, cafeteria, data, size.width, size.height)
                    }
                    manager.updateAppWidget(widgetId, RemoteViews(sizeViews))
                    return
                }
            }

            manager.updateAppWidget(
                widgetId,
                createFallbackRemoteViews(context, cafeteria, data, options)
            )
        }

        /** 크기 목록이 없는 런처에도 각 방향의 실제 영역으로 측정한 뷰를 제공한다. */
        private fun createFallbackRemoteViews(
            context: Context, cafeteria: Int, data: WidgetMealData, options: Bundle,
        ): RemoteViews {
            val portraitWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                .takeIf { it > 0 }?.toFloat() ?: 160f
            val portraitHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
                .takeIf { it > 0 }?.toFloat() ?: 150f
            val landscapeWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
                .takeIf { it > 0 }?.toFloat() ?: portraitWidth
            val landscapeHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
                .takeIf { it > 0 }?.toFloat() ?: portraitHeight
            return RemoteViews(
                createRemoteViews(context, cafeteria, data, landscapeWidth, landscapeHeight),
                createRemoteViews(context, cafeteria, data, portraitWidth, portraitHeight),
            )
        }

        private fun createRemoteViews(
            context: Context,
            cafeteria: Int,
            data: WidgetMealData,
            widthDp: Float,
            heightDp: Float
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_2x2)
            val cafeteriaName = context.getString(cafeteriaNameResId(cafeteria))
            val mealLabel = data.mealLabel(context)

            views.setTextViewText(R.id.tv_cafeteria_name, cafeteriaName)
            views.setTextViewText(R.id.tv_meal_of_day, mealLabel)
            views.bindFoodType(context, R.id.tv_food_type, cafeteria)

            val twoColumnMenu = usesTwoColumnMenu(widthDp)
            val menuSp   = WIDGET_MENU_MIN_TEXT_SP
            val statusSp = calcStatusTextSp(menuSp)
            val headerSp = calcHeaderTextSp(menuSp)
            // AppWidgetManager가 보고한 크기를 그대로 측정해야 최소 크기에서도 남는 메뉴
            // 높이를 온전히 사용한다. 전체 크기를 임의로 축소하면 고정 헤더/상태 영역 때문에
            // 축소분이 메뉴 영역에 집중되어 실제보다 한 줄 이상 일찍 말줄임된다.
            val widthPx  = dpToPx(context, widthDp).toInt()
            val heightPx = dpToPx(context, heightDp).toInt()

            val statusDisplay = data.operatingStatus(context, cafeteria)

            fun setup(root: View) {
                root.findViewById<TextView>(R.id.tv_cafeteria_name).apply {
                    text = cafeteriaName
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, headerSp)
                }
                root.findViewById<TextView>(R.id.tv_meal_of_day).apply {
                    text = mealLabel
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<TextView>(R.id.tv_food_type).apply {
                    val foodTypeResId = cafeteriaFoodTypeResId(cafeteria)
                    visibility = if (foodTypeResId != null) View.VISIBLE else View.GONE
                    if (foodTypeResId != null) text = context.getString(foodTypeResId)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, headerSp)
                }
                root.findViewById<TextView>(R.id.tv_status).bindOperatingStatusForMeasure(statusDisplay, statusSp)
                root.findViewById<TextView>(R.id.tv_menu).apply {
                    visibility = if (twoColumnMenu) View.GONE else View.VISIBLE
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
                root.findViewById<View>(R.id.menu_columns).visibility =
                    if (twoColumnMenu) View.VISIBLE else View.GONE
                listOf(R.id.tv_menu_left, R.id.tv_menu_right).forEach { menuViewId ->
                    root.findViewById<TextView>(menuViewId)
                        .setTextSize(TypedValue.COMPLEX_UNIT_SP, menuSp)
                }
            }

            val items = data.menuItems(context, cafeteria)
            val menu = layoutWidgetMenu(context, widthPx, heightPx, items, twoColumnMenu, ::setup)
            if (twoColumnMenu) {
                views.setViewVisibility(R.id.tv_menu, View.GONE)
                views.setViewVisibility(R.id.menu_columns, View.VISIBLE)
                views.setTextViewText(R.id.tv_menu_left, menu.leftText)
                views.setTextViewText(R.id.tv_menu_right, menu.rightText)
                views.setInt(R.id.tv_menu_left, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)
                views.setInt(R.id.tv_menu_right, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)
            } else {
                views.setViewVisibility(R.id.tv_menu, View.VISIBLE)
                views.setViewVisibility(R.id.menu_columns, View.GONE)
                views.setTextViewText(R.id.tv_menu, menu.leftText)
                views.setInt(R.id.tv_menu, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)
            }

            views.bindOperatingStatus(R.id.tv_status, statusDisplay)

            views.applyTextSizes(
                menu.textSizeSp, listOf(R.id.tv_menu, R.id.tv_menu_left, R.id.tv_menu_right),
                statusSp, listOf(R.id.tv_status),
                headerSp = headerSp,
                headerIds = listOf(R.id.tv_cafeteria_name, R.id.tv_food_type)
            )
            views.setTextViewTextSize(R.id.tv_meal_of_day, TypedValue.COMPLEX_UNIT_SP, menuSp)
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))
            return views
        }
    }
}
