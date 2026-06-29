package pro.hexa.meal.meal_client

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 2x2 위젯과 4x2 운영상태 위젯의 식당 선택 설정 화면.
 * 선택 목록: 기숙사(한식) / 기숙사(할랄) / 학생 / 교직원
 */
class BapUWidgetSingleConfigActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var selectedCafeteria = CAFE_DORM_KOREAN

    private lateinit var items: List<LinearLayout>
    private lateinit var dots: List<View>

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

        setContentView(R.layout.widget_config_single)

        // 상단바 높이만큼 top padding 추가 (좌우 padding은 XML 유지)
        val root = findViewById<LinearLayout>(R.id.root_config_single)
        root.setOnApplyWindowInsetsListener { v, insets ->
            val topInset = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                insets.getInsets(WindowInsets.Type.statusBars()).top
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetTop
            }
            val p24 = (24 * resources.displayMetrics.density).toInt()
            v.setPadding(p24, p24 + topInset, p24, p24)
            insets
        }

        // CAFE_OPTIONS 순서와 동일하게 [한식, 할랄, 학생, 교직원]
        items = listOf(
            findViewById(R.id.item_dorm_korean),
            findViewById(R.id.item_dorm_halal),
            findViewById(R.id.item_student),
            findViewById(R.id.item_faculty),
        )
        dots = listOf(
            findViewById(R.id.dot_dorm_korean),
            findViewById(R.id.dot_dorm_halal),
            findViewById(R.id.dot_student),
            findViewById(R.id.dot_faculty),
        )

        selectedCafeteria = loadSingleCafeteria(this, appWidgetId)
        refreshSelection()

        items.forEachIndexed { index, layout ->
            layout.setOnClickListener {
                selectedCafeteria = CAFE_OPTIONS[index]
                refreshSelection()
            }
        }

        findViewById<Button>(R.id.btn_confirm).setOnClickListener {
            saveSingleCafeteria(this, appWidgetId, selectedCafeteria)
            Log.d(TAG, "saved cafeteria=$selectedCafeteria for widget=$appWidgetId")

            BapUWidgetUpdateWorker.enqueueOneTime(this)

            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
            finish()
        }
    }

    private fun refreshSelection() {
        val selectedIndex = CAFE_OPTIONS.indexOf(selectedCafeteria).takeIf { it >= 0 } ?: 0
        items.forEachIndexed { index, layout ->
            val selected = index == selectedIndex
            layout.setBackgroundResource(
                if (selected) R.drawable.widget_config_item_selected
                else R.drawable.widget_config_item_normal
            )
            val tv = layout.getChildAt(0) as? TextView
            tv?.setTextColor(getColor(R.color.config_text_primary))
            dots[index].visibility = if (selected) View.VISIBLE else View.GONE
        }
    }

    companion object {
        private const val TAG = "BapUWidgetSingleConfig"
    }
}
