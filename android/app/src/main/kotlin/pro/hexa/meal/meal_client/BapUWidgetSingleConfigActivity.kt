package pro.hexa.meal.meal_client

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 위젯의 식당 선택 설정 화면.
 * 선택 목록: 기숙사(한식) / 기숙사(할랄) / 학생 / 교직원
 * 상단에 실제 위젯 레이아웃(widget_2x2)을 inflate한 라이브 미리보기를 보여준다.
 */
class BapUWidgetSingleConfigActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var selectedCafeteria = CAFE_DORM_KOREAN
    private var previewData: WidgetMealData? = null

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

        // 상단바 높이만큼 top padding 추가 (콘텐츠 패딩은 내부 LinearLayout이 유지)
        val root = findViewById<View>(R.id.root_config_single)
        root.setOnApplyWindowInsetsListener { v, insets ->
            val topInset = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                insets.getInsets(WindowInsets.Type.statusBars()).top
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetTop
            }
            v.setPadding(0, topInset, 0, 0)
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
        stylePreview()
        refreshSelection()

        // 미리보기용 캐시 데이터 로드 (cache-only라 가볍지만 파일 IO는 스레드로)
        Thread {
            val data = BapUWidgetFetcher.fetch(applicationContext)
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                previewData = data
                bindPreview()
            }
        }.start()

        items.forEachIndexed { index, layout ->
            layout.setOnClickListener {
                selectedCafeteria = CAFE_OPTIONS[index]
                refreshSelection()
            }
        }

        findViewById<Button>(R.id.btn_confirm).setOnClickListener {
            saveSingleCafeteria(this, appWidgetId, selectedCafeteria)
            Log.d(TAG, "saved cafeteria=$selectedCafeteria for widget=$appWidgetId")

            val ctx = applicationContext
            Thread {
                try {
                    BapUWidgetUpdateDispatcher.renderAllWidgets(ctx)
                } catch (e: Exception) {
                    Log.e(TAG, "widget render failed", e)
                }
            }.start()

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
        bindPreview()
    }

    /**
     * 미리보기 카드의 텍스트 크기를 실제 위젯 렌더 값(12sp 고정 체계)에 맞춘다.
     * 그림자는 View.elevation 대신 XML의 backing 사각형으로 대체했다(elevation 그림자가
     * 렌더러/기기에 따라 지저분하게 나오는 문제가 있었음).
     */
    private fun stylePreview() {
        val preview = findViewById<View>(R.id.preview_widget) ?: return
        preview.findViewById<TextView>(R.id.tv_cafeteria_name)
            .setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        preview.findViewById<TextView>(R.id.tv_food_type)
            .setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        preview.findViewById<TextView>(R.id.tv_meal_of_day)
            .setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        preview.findViewById<TextView>(R.id.tv_menu)
            .setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        preview.findViewById<TextView>(R.id.tv_status)
            .setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
    }

    /**
     * 현재 선택된 식당 기준으로 미리보기 카드를 다시 채운다.
     * 카드는 [PREVIEW_SIZE_DP] 고정 크기이므로, 실제 위젯이 쓰는 것과 같은
     * [truncateMenuByRealLayout]로 정확히 그만큼만 채우고 넘치면 "..."로 표시한다
     * (전체를 그냥 이어붙이면 고정 카드 밖으로 넘친 마지막 줄이 예고 없이 잘려 보인다).
     */
    private fun bindPreview() {
        val preview = findViewById<View>(R.id.preview_widget) ?: return
        val cafeteria = selectedCafeteria

        val cafeteriaName = getString(cafeteriaNameResId(cafeteria))
        val foodTypeResId = cafeteriaFoodTypeResId(cafeteria)
        val foodTypeText = foodTypeResId?.let { getString(it) }

        val data = previewData
        val mealLabel: String
        val menuItems: List<String>
        val statusDisplay: Pair<Int, String>
        if (data == null || data.isError) {
            // 캐시가 아직 없음(신규 설치 직후 등) — 샘플 데이터로 모양만 보여준다
            mealLabel = getString(R.string.meal_lunch)
            menuItems = getString(R.string.widget_preview_menu).split("\n")
            statusDisplay = Pair(getColor(R.color.widget_status_open), getString(R.string.status_open))
        } else {
            mealLabel = data.mealLabel(this)
            menuItems = menuFromData(data, cafeteria).filter { it.isNotEmpty() }
            statusDisplay = data.operatingStatus(this, cafeteria)
        }

        preview.findViewById<TextView>(R.id.tv_cafeteria_name).text = cafeteriaName
        preview.findViewById<TextView>(R.id.tv_food_type).apply {
            visibility = if (foodTypeText != null) View.VISIBLE else View.GONE
            if (foodTypeText != null) text = foodTypeText
        }
        preview.findViewById<TextView>(R.id.tv_meal_of_day).text = mealLabel
        preview.findViewById<TextView>(R.id.tv_status).apply {
            visibility = View.VISIBLE
            text = statusDisplay.second
            setTextColor(statusDisplay.first)
        }

        fun setupMeasure(root: View) {
            root.findViewById<TextView>(R.id.tv_cafeteria_name).apply {
                text = cafeteriaName
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            }
            root.findViewById<TextView>(R.id.tv_meal_of_day).apply {
                text = mealLabel
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            }
            root.findViewById<TextView>(R.id.tv_food_type).apply {
                visibility = if (foodTypeText != null) View.VISIBLE else View.GONE
                if (foodTypeText != null) text = foodTypeText
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            }
            root.findViewById<TextView>(R.id.tv_status).bindOperatingStatusForMeasure(statusDisplay, 11f)
        }

        val previewSizePx = dpToPx(this, PREVIEW_SIZE_DP).toInt()
        val menuView = preview.findViewById<TextView>(R.id.tv_menu)
        menuView.text = if (menuItems.isEmpty()) {
            getString(R.string.widget_no_menu)
        } else {
            truncateMenuByRealLayout(
                this, R.layout.widget_2x2, R.id.tv_menu, previewSizePx, previewSizePx, menuItems, ::setupMeasure
            )
        }
    }

    companion object {
        private const val TAG = "BapUWidgetSingleConfig"

        /** widget_config_single.xml의 preview_widget include 크기(180dp)와 반드시 일치해야 한다. */
        private const val PREVIEW_SIZE_DP = 180f
    }
}
