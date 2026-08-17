package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.util.Log
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView

class BapUWidget2x2Provider : BapUBaseWidgetProvider() {

    override val TAG = Companion.TAG

    override fun performUpdate(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData) =
        Companion.updateWidget(context, manager, widgetId, data)

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (id in appWidgetIds) clearWidgetConfig(context, id)
    }

    companion object {
        const val TAG = "BapUWidget2x2"

        @Suppress("DEPRECATION")
        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int, data: WidgetMealData) {
            Log.d(TAG, "updateWidget id=$widgetId data=$data")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val sizes = manager.getAppWidgetOptions(widgetId)
                    .getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                    ?.filter { it.width > 0f && it.height > 0f }
                    ?.distinct()
                    .orEmpty()
                if (sizes.isNotEmpty()) {
                    Log.d(TAG, "using size-specific RemoteViews: $sizes")
                    val sizeViews = sizes.associateWith { size ->
                        createRemoteViews(context, widgetId, data, size.width, size.height)
                    }
                    manager.updateAppWidget(widgetId, RemoteViews(sizeViews))
                    return
                }
            }

            val widthDp = widgetWidthDp(manager, widgetId).toFloat()
            val heightDp = widgetHeightDp(manager, widgetId).toFloat()
            manager.updateAppWidget(
                widgetId,
                createRemoteViews(context, widgetId, data, widthDp, heightDp)
            )
        }

        private fun createRemoteViews(
            context: Context,
            widgetId: Int,
            data: WidgetMealData,
            widthDp: Float,
            heightDp: Float
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_2x2)
            val cafeteria = loadSingleCafeteria(context, widgetId)
            val cafeteriaName = context.getString(cafeteriaNameResId(cafeteria))
            val mealLabel = data.mealLabel(context)

            views.setTextViewText(R.id.tv_cafeteria_name, cafeteriaName)
            views.setTextViewText(R.id.tv_meal_of_day, mealLabel)
            views.bindFoodType(context, R.id.tv_food_type, cafeteria)

            val twoColumnMenu = usesTwoColumnMenu(widthDp)
            val menuSp   = calcMenuTextSp(widthDp.toInt(), columns = if (twoColumnMenu) 2 else 1)
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
            if (twoColumnMenu) {
                val (leftMenu, rightMenu) = truncateMenuTwoColumnsByRealLayout(
                    context, R.layout.widget_2x2, R.id.tv_menu_left, R.id.tv_menu_right,
                    widthPx, heightPx, items, ::setup
                )
                views.setViewVisibility(R.id.tv_menu, View.GONE)
                views.setViewVisibility(R.id.menu_columns, View.VISIBLE)
                views.setTextViewText(R.id.tv_menu_left, leftMenu)
                views.setTextViewText(R.id.tv_menu_right, rightMenu)
                views.setInt(R.id.tv_menu_left, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)
                views.setInt(R.id.tv_menu_right, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)
            } else {
                val menuText = truncateMenuByRealLayout(
                    context, R.layout.widget_2x2, R.id.tv_menu, widthPx, heightPx, items, ::setup
                )
                views.setViewVisibility(R.id.tv_menu, View.VISIBLE)
                views.setViewVisibility(R.id.menu_columns, View.GONE)
                views.setTextViewText(R.id.tv_menu, menuText)
                views.setInt(R.id.tv_menu, "setMaxLines", WIDGET_MENU_MAX_LINES_SAFETY_CAP)
            }

            views.bindOperatingStatus(R.id.tv_status, statusDisplay)

            views.applyTextSizes(
                menuSp, listOf(R.id.tv_menu, R.id.tv_menu_left, R.id.tv_menu_right, R.id.tv_meal_of_day),
                statusSp, listOf(R.id.tv_status),
                headerSp = headerSp,
                headerIds = listOf(R.id.tv_cafeteria_name, R.id.tv_food_type)
            )
            views.setOnClickPendingIntent(R.id.widget_root, makeLaunchPendingIntent(context))
            return views
        }
    }
}
