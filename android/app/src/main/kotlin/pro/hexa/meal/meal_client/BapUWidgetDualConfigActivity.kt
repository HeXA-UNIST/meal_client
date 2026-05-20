package pro.hexa.meal.meal_client

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 4x2 두 식당 위젯의 식당 쌍 선택 설정 화면.
 * 선택 목록: 기숙사(한식) / 기숙사(할랄) / 학생 / 교직원
 */
class BapUWidgetDualConfigActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var selected0 = CAFE_DORM_KOREAN
    private var selected1 = CAFE_STUDENT

    private lateinit var items0: List<LinearLayout>
    private lateinit var dots0: List<View>
    private lateinit var items1: List<LinearLayout>
    private lateinit var dots1: List<View>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            Log.e(TAG, "invalid widget id")
            finish()
            return
        }

        setContentView(R.layout.widget_config_dual)

        // CAFE_OPTIONS 순서와 동일하게 [한식, 할랄, 학생, 교직원]
        items0 = listOf(
            findViewById(R.id.item0_dorm_korean),
            findViewById(R.id.item0_dorm_halal),
            findViewById(R.id.item0_student),
            findViewById(R.id.item0_faculty),
        )
        dots0 = listOf(
            findViewById(R.id.dot0_dorm_korean),
            findViewById(R.id.dot0_dorm_halal),
            findViewById(R.id.dot0_student),
            findViewById(R.id.dot0_faculty),
        )
        items1 = listOf(
            findViewById(R.id.item1_dorm_korean),
            findViewById(R.id.item1_dorm_halal),
            findViewById(R.id.item1_student),
            findViewById(R.id.item1_faculty),
        )
        dots1 = listOf(
            findViewById(R.id.dot1_dorm_korean),
            findViewById(R.id.dot1_dorm_halal),
            findViewById(R.id.dot1_student),
            findViewById(R.id.dot1_faculty),
        )

        val (c0, c1) = loadDualCafeterias(this, appWidgetId)
        selected0 = c0
        selected1 = c1
        refreshSelection()

        items0.forEachIndexed { index, layout ->
            layout.setOnClickListener {
                selected0 = CAFE_OPTIONS[index]
                refreshSelection()
            }
        }
        items1.forEachIndexed { index, layout ->
            layout.setOnClickListener {
                selected1 = CAFE_OPTIONS[index]
                refreshSelection()
            }
        }

        findViewById<Button>(R.id.btn_confirm).setOnClickListener {
            saveDualCafeterias(this, appWidgetId, selected0, selected1)
            Log.d(TAG, "saved c0=$selected0 c1=$selected1 for widget=$appWidgetId")

            val manager = AppWidgetManager.getInstance(this)
            val ctx = applicationContext
            val widgetId = appWidgetId
            Thread {
                try {
                    val data = BapUWidgetFetcher.fetch()
                    BapUWidget4x2DualProvider.updateWidget(ctx, manager, widgetId, data)
                } catch (e: Exception) {
                    Log.e(TAG, "update failed", e)
                }
            }.start()

            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
            finish()
        }
    }

    private fun refreshSelection() {
        applyGroup(items0, dots0, selected0)
        applyGroup(items1, dots1, selected1)
    }

    private fun applyGroup(items: List<LinearLayout>, dots: List<View>, selected: Int) {
        val selectedIndex = CAFE_OPTIONS.indexOf(selected).takeIf { it >= 0 } ?: 0
        items.forEachIndexed { index, layout ->
            val isSelected = index == selectedIndex
            layout.setBackgroundResource(
                if (isSelected) R.drawable.widget_config_item_selected
                else R.drawable.widget_config_item_normal
            )
            val tv = layout.getChildAt(0) as? TextView
            tv?.setTextColor(
                if (isSelected) getColor(R.color.black)
                else getColor(R.color.white)
            )
            dots[index].visibility = if (isSelected) View.VISIBLE else View.GONE
        }
    }

    companion object {
        private const val TAG = "BapUWidgetDualConfig"
    }
}
