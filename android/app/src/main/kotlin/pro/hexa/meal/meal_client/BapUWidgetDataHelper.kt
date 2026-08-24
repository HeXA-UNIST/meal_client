package pro.hexa.meal.meal_client

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences  // getWidgetConfigPrefs 에서 사용
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView

/** 실측 계산이 어긋나더라도 무한정 늘어나지 않도록 두는 하드 상한(안전장치). */
const val WIDGET_MENU_MAX_LINES_SAFETY_CAP = 20

/** TextView의 내용 높이와 부모가 배정한 높이 사이에서 발생할 수 있는 픽셀 반올림 오차. */
private const val WIDGET_MENU_MEASURE_ROUNDING_TOLERANCE_PX = 1

/** AOSP Launcher3 셀 공식상 4칸 너비에 해당하는 최소 크기. */
const val WIDGET_TWO_COLUMN_MIN_WIDTH_DP = 250

// 위젯 인스턴스별 설정 저장용
private const val WIDGET_CONFIG_PREFS = "bapu_widget_config"

// ─── 식당 인덱스 상수 ────────────────────────────────────────────────────────
// 기존 0(기숙사)/1(학생)/2(교직원) 저장값과 하위 호환을 유지한다.
const val CAFE_DORM_KOREAN = 0   // 기숙사 한식
const val CAFE_DORM_HALAL  = 10  // 기숙사 할랄 (10 = 기존 1·2와 충돌 없음)
const val CAFE_STUDENT     = 1   // 학생 식당
const val CAFE_FACULTY     = 2   // 교직원 식당

/** UI 순서대로 나열한 식당 상수 목록 (설정 화면 항목 순서와 일치). */
val CAFE_OPTIONS = listOf(CAFE_DORM_KOREAN, CAFE_DORM_HALAL, CAFE_STUDENT, CAFE_FACULTY)

/** 식당 설정 화면에서 사용하는 이름 리소스 ID (선택 목록용). */
fun cafeteriaConfigNameResId(cafeteria: Int): Int = when (cafeteria) {
    CAFE_DORM_KOREAN -> R.string.cafeteria_dorm_korean
    CAFE_DORM_HALAL  -> R.string.cafeteria_dorm_halal
    CAFE_STUDENT     -> R.string.cafeteria_student
    CAFE_FACULTY     -> R.string.cafeteria_faculty
    else             -> R.string.cafeteria_student
}

fun getWidgetConfigPrefs(context: Context): SharedPreferences =
    context.getSharedPreferences(WIDGET_CONFIG_PREFS, Context.MODE_PRIVATE)

/**
 * [layoutResId] 위젯 레이아웃을 오프스크린으로 inflate & measure 해서, [menuViewId] TextView가
 * 후보 텍스트를 실제로 필요한 만큼 그리려면 배정된 높이를 넘는지(=화면에서 다른 뷰와 겹치게
 * 되는지) 직접 확인한다. 항목을 하나씩 채워보다가 넘치는 시점에 "..."으로 대체하고, 그것도
 * 안 들어가면 마지막으로 채운 항목을 통째로 "..."으로 교체한다.
 *
 * StaticLayout으로 직접 폭 추정하는 대신 실제 레이아웃을 그대로 inflate하는 이유: 이 앱의
 * 커스텀 폰트를 `ResourcesCompat.getFont()`로 직접 불러오면 일부 기기에서 스레드와 무관하게
 * 예외가 나는데, `LayoutInflater`를 통한 정상적인 inflate는 같은 폰트를 문제없이 해석한다.
 * 그래서 실제 폰트/줄바꿈/여백을 전부 안드로이드의 실제 레이아웃 계산에 맡긴다.
 *
 * @param setup 헤더/운영상태/텍스트 크기 등 메뉴를 뺀 나머지를 채우는 콜백. 후보마다 새로
 *              inflate 하므로 매번 호출된다.
 */
fun truncateMenuByRealLayout(
    context: Context,
    layoutResId: Int,
    menuViewId: Int,
    widthPx: Int,
    heightPx: Int,
    items: List<String>,
    setup: (root: View) -> Unit
): String {
    val filtered = items.filter { it.isNotEmpty() }
    if (filtered.isEmpty()) return "-"

    fun fits(text: String): Boolean {
        val root = LayoutInflater.from(context).inflate(layoutResId, null)
        setup(root)
        val menuView = root.findViewById<TextView>(menuViewId)
        menuView.maxLines = WIDGET_MENU_MAX_LINES_SAFETY_CAP
        menuView.text = text

        // 1단계: 실제 위젯 크기로 전체 레이아웃을 측정해서 tv_menu에 배정되는 높이를 구한다.
        root.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY)
        )
        val assignedHeight = menuView.measuredHeight
        val menuWidthSpec = View.MeasureSpec.makeMeasureSpec(menuView.measuredWidth, View.MeasureSpec.EXACTLY)

        // 2단계: 폭/높이 둘 다 EXACTLY로 측정하면 TextView가 내용 기반 계산을 건너뛰어
        // getLayout()이 비어있을 수 있다. 같은 텍스트/폭으로 menuView만 높이 제한 없이
        // 다시 측정해서 실제로 필요한 높이를 직접 얻는다.
        menuView.measure(menuWidthSpec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        val neededHeight = menuView.measuredHeight

        return fitsWithinWidgetMenuHeight(neededHeight, assignedHeight)
    }

    val fullMenu = filtered.joinToString("\n")
    if (fits(fullMenu)) return fullMenu

    // 말줄임표에 한 줄 전체를 예약하지 않고 마지막으로 표시 가능한 메뉴 뒤에 붙인다.
    // 따라서 5줄 공간에는 메뉴 5개와 이후 항목이 있음을 함께 표시할 수 있다.
    for (visibleCount in filtered.lastIndex downTo 1) {
        val candidate = appendInlineMenuEllipsis(filtered.take(visibleCount)).joinToString("\n")
        if (fits(candidate)) return candidate
    }

    for (visibleCount in filtered.lastIndex downTo 0) {
        val candidate = (filtered.take(visibleCount) + "...").joinToString("\n")
        if (fits(candidate)) return candidate
    }
    return "..."
}

/** 4칸 이상으로 넓힌 위젯에서 메뉴를 2열로 표시할지 결정한다. */
fun usesTwoColumnMenu(widthDp: Number): Boolean = widthDp.toFloat() >= WIDGET_TWO_COLUMN_MIN_WIDTH_DP

/** 마지막 표시 메뉴와 말줄임표를 같은 줄에 배치한다. */
fun appendInlineMenuEllipsis(items: List<String>): List<String> = when {
    items.isEmpty() -> listOf("...")
    else -> items.dropLast(1) + "${items.last()}…"
}

/** 읽는 순서를 유지하면서 앞 절반은 왼쪽, 나머지는 오른쪽 열에 배치한다. */
fun splitMenuItemsIntoColumns(items: List<String>): Pair<List<String>, List<String>> {
    val splitIndex = (items.size + 1) / 2
    return items.take(splitIndex) to items.drop(splitIndex)
}

/**
 * 2열 메뉴 레이아웃을 실제 크기로 측정해 두 열에 들어가는 가장 긴 앞부분을 찾는다.
 * 모든 항목이 들어가지 않으면 마지막 표시 메뉴 뒤에 말줄임표를 붙인다.
 */
fun truncateMenuTwoColumnsByRealLayout(
    context: Context,
    layoutResId: Int,
    leftMenuViewId: Int,
    rightMenuViewId: Int,
    widthPx: Int,
    heightPx: Int,
    items: List<String>,
    setup: (root: View) -> Unit
): Pair<String, String> {
    val filtered = items.filter { it.isNotEmpty() }
    if (filtered.isEmpty()) return "-" to ""

    fun fits(left: String, right: String): Boolean {
        val root = LayoutInflater.from(context).inflate(layoutResId, null)
        setup(root)
        val menuViews = listOf(
            root.findViewById<TextView>(leftMenuViewId),
            root.findViewById<TextView>(rightMenuViewId)
        )
        menuViews[0].text = left
        menuViews[1].text = right
        menuViews.forEach { it.maxLines = WIDGET_MENU_MAX_LINES_SAFETY_CAP }

        root.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY)
        )

        return menuViews.all { menuView ->
            val assignedHeight = menuView.measuredHeight
            val widthSpec = View.MeasureSpec.makeMeasureSpec(menuView.measuredWidth, View.MeasureSpec.EXACTLY)
            menuView.measure(widthSpec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            fitsWithinWidgetMenuHeight(menuView.measuredHeight, assignedHeight)
        }
    }

    fun fittingColumns(displayItems: List<String>): Pair<String, String>? {
        if (displayItems.size == 1) {
            val text = displayItems.single()
            return if (fits(text, "")) text to "" else null
        }

        val (balancedLeftItems, balancedRightItems) = splitMenuItemsIntoColumns(displayItems)
        val balancedLeft = balancedLeftItems.joinToString("\n")
        val balancedRight = balancedRightItems.joinToString("\n")
        if (fits(balancedLeft, balancedRight)) return balancedLeft to balancedRight

        val balancedSplit = (displayItems.size + 1) / 2
        val splitCandidates = (1 until displayItems.size)
            .filter { it != balancedSplit }
            .sortedBy { splitIndex -> kotlin.math.abs(splitIndex - balancedSplit) }
        for (splitIndex in splitCandidates) {
            val left = displayItems.take(splitIndex).joinToString("\n")
            val right = displayItems.drop(splitIndex).joinToString("\n")
            if (fits(left, right)) return left to right
        }
        return null
    }

    fittingColumns(filtered)?.let { return it }
    for (visibleCount in filtered.lastIndex downTo 1) {
        fittingColumns(appendInlineMenuEllipsis(filtered.take(visibleCount)))?.let { return it }
    }
    for (visibleCount in filtered.lastIndex downTo 0) {
        fittingColumns(filtered.take(visibleCount) + "...")?.let { return it }
    }
    return "..." to ""
}

/** 실제 레이아웃 측정 과정의 1px 반올림 차이만 허용하고, 내용 한 줄의 초과는 거부한다. */
internal fun fitsWithinWidgetMenuHeight(neededHeight: Int, assignedHeight: Int): Boolean =
    neededHeight <= assignedHeight + WIDGET_MENU_MEASURE_ROUNDING_TOLERANCE_PX

data class OperatingPeriod(val startH: Int, val startM: Int, val endH: Int, val endM: Int)

enum class OperatingStatus {
    BEFORE_OPEN, OPEN, CLOSING_SOON, CLOSED,
    /** 오늘 이 식당/끼니의 운영시간 자체가 없음 (예: 주말 학생·교직원 식당, 교직원 조식). */
    NO_SERVICE,
}

/**
 * @param nextStartH/[nextStartM] BEFORE_OPEN일 때 다음 운영 시작 시각 ("17:30부터 운영" 등에 사용).
 *        BEFORE_OPEN 외 상태에서는 의미 없음(0).
 */
data class OperatingResult(
    val status: OperatingStatus,
    val nextStartH: Int = 0,
    val nextStartM: Int = 0,
)

// ─── 위젯 인스턴스별 식당 설정 ───────────────────────────────────────────────

fun loadSingleCafeteria(context: Context, widgetId: Int): Int =
    getWidgetConfigPrefs(context).getInt("config_${widgetId}_cafeteria", CAFE_DORM_KOREAN)

fun saveSingleCafeteria(context: Context, widgetId: Int, cafeteria: Int) =
    getWidgetConfigPrefs(context).edit()
        .putInt("config_${widgetId}_cafeteria", cafeteria)
        .apply()

fun clearWidgetConfig(context: Context, widgetId: Int) =
    getWidgetConfigPrefs(context).edit()
        .remove("config_${widgetId}_cafeteria")
        // 과거 Dual 위젯이 쓰던 키 — 남아있을 수 있어 함께 정리한다.
        .remove("config_${widgetId}_cafeteria_0")
        .remove("config_${widgetId}_cafeteria_1")
        .apply()

// ─── 식당 인덱스 → 리소스 매핑 ──────────────────────────────────────────────

/** 위젯 헤더에 표시하는 식당 이름 리소스 (기숙사 한식/할랄 모두 "기숙사 식당"). */
fun cafeteriaNameResId(cafeteria: Int): Int = when (cafeteria) {
    CAFE_DORM_KOREAN, CAFE_DORM_HALAL -> R.string.cafeteria_dormitory
    CAFE_STUDENT                       -> R.string.cafeteria_student
    CAFE_FACULTY                       -> R.string.cafeteria_faculty
    else                               -> R.string.cafeteria_student
}

/**
 * 헤더 옆에 표시할 음식 종류 리소스 ID.
 * 기숙사 식당만 음식 종류를 표시하며 null이면 tv_food_type을 GONE으로 설정한다.
 */
fun cafeteriaFoodTypeResId(cafeteria: Int): Int? = when (cafeteria) {
    CAFE_DORM_KOREAN -> R.string.food_korean
    CAFE_DORM_HALAL  -> R.string.food_halal
    else             -> null
}

fun mealOfDayResId(mealOfDay: Int): Int = when (mealOfDay) {
    0 -> R.string.meal_breakfast
    1 -> R.string.meal_lunch
    else -> R.string.meal_dinner
}

// ─── 기기별 동적 텍스트 크기 계산 ─────────────────────────────────────────────

/** AppWidget 옵션에서 세로 모드 최소 너비(dp)를 읽는다. */
fun widgetWidthDp(manager: AppWidgetManager, widgetId: Int): Int {
    val min = manager.getAppWidgetOptions(widgetId)
        .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
    return if (min > 0) min else 160
}

/**
 * AppWidget 옵션에서 세로 모드 실제 높이(dp)를 읽는다.
 * MIN_HEIGHT = 가로 모드(더 좁은 방향) 높이, MAX_HEIGHT = 세로 모드(더 큰 방향) 높이.
 * 줄 수 계산은 세로 모드 기준이므로 MAX_HEIGHT 를 사용한다.
 */
fun widgetHeightDp(manager: AppWidgetManager, widgetId: Int): Int {
    val max = manager.getAppWidgetOptions(widgetId)
        .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
    return if (max > 0) max else 150
}

/**
 * 메뉴 텍스트 크기(sp). 위젯 크기와 무관하게 항상 동일한 크기를 쓴다
 * (2x2와 확대 상태에서 폰트가 달라지지 않도록). 공간이 부족하면 실측 truncate가
 * 항목 수를 줄이는 것으로 대응한다.
 */
fun calcMenuTextSp(widthDp: Int, columns: Int = 1): Float = 12f

/** 메뉴 sp 에서 운영 상태 텍스트 sp 를 계산한다 (시안 비율: 메뉴보다 1sp 작게, 최소 8sp). */
fun calcStatusTextSp(menuSp: Float): Float = (menuSp - 1f).coerceAtLeast(8f)

/** 메뉴 sp 에서 헤더(식당명·음식종류) 텍스트 sp 를 계산한다 (시안 비율: 메뉴보다 1sp 크게). */
fun calcHeaderTextSp(menuSp: Float): Float = menuSp + 1f

/** dp 값을 현재 기기의 실제 px 로 변환한다. */
fun dpToPx(context: Context, dp: Float): Float =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, context.resources.displayMetrics)

/**
 * RemoteViews 에 메뉴/상태/헤더 텍스트 크기를 일괄 적용한다.
 * SP 단위로 설정하므로 사용자의 글자 크기 접근성 설정도 반영된다.
 */
fun RemoteViews.applyTextSizes(
    menuSp: Float, menuIds: List<Int>,
    statusSp: Float, statusIds: List<Int>,
    headerSp: Float = menuSp + 1f, headerIds: List<Int> = emptyList()
) {
    for (id in menuIds)   setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, menuSp)
    for (id in statusIds) setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, statusSp)
    for (id in headerIds) setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, headerSp)
}

/**
 * cafeteria/mealOfDay 기준 운영 상태의 (색상, 표시 문구)를 반환한다.
 * 메뉴에 실제로 쓸 수 있는 높이를 계산할 때도 이 문구를 그대로 실측에 사용해야 하므로
 * RemoteViews 에 바로 적용하지 않고 별도 함수로 분리되어 있다.
 *
 * info.json 캐시 자체를 못 불러온 경우(운영시간 데이터 없음)는 상태 줄을 숨기지 않고
 * "-"로 표시한다 — 오늘 미운영(NO_SERVICE, "미운영")과는 다른, "몰라서 못 보여줌" 상태.
 */
fun operatingStatusDisplay(context: Context, result: OperatingResult?): Pair<Int, String> {
    result
        ?: return Pair(context.getColor(R.color.widget_status_closed), context.getString(R.string.widget_no_menu))
    return when (result.status) {
        OperatingStatus.BEFORE_OPEN  -> Pair(
            context.getColor(R.color.widget_status_before),
            context.getString(R.string.status_before_open, result.nextStartH, result.nextStartM)
        )
        OperatingStatus.OPEN         -> Pair(
            context.getColor(R.color.widget_status_open),
            context.getString(R.string.status_open)
        )
        OperatingStatus.CLOSING_SOON -> Pair(
            context.getColor(R.color.widget_status_closing),
            context.getString(R.string.status_closing_soon)
        )
        OperatingStatus.CLOSED       -> Pair(
            context.getColor(R.color.widget_status_closed),
            context.getString(R.string.status_closed)
        )
        OperatingStatus.NO_SERVICE   -> Pair(
            context.getColor(R.color.widget_status_closed),
            context.getString(R.string.status_no_service)
        )
    }
}

fun RemoteViews.bindOperatingStatus(statusViewId: Int, display: Pair<Int, String>) {
    setViewVisibility(statusViewId, View.VISIBLE)
    setTextViewText(statusViewId, display.second)
    setTextColor(statusViewId, display.first)
}

fun TextView.bindOperatingStatusForMeasure(display: Pair<Int, String>, statusSp: Float) {
    visibility = View.VISIBLE
    text = display.second
    setTextSize(TypedValue.COMPLEX_UNIT_SP, statusSp)
}

/** 위젯을 탭하면 앱을 실행하는 PendingIntent 를 만든다. */
fun makeLaunchPendingIntent(context: Context): PendingIntent {
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: Intent(Intent.ACTION_MAIN).apply {
            setPackage(context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    return PendingIntent.getActivity(
        context, 0, intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
}

/**
 * RemoteViews 에 cafeteria 인덱스에 맞는 음식 종류 라벨을 설정한다.
 * 기숙사가 아니면 tv_food_type 을 GONE 처리한다.
 */
fun RemoteViews.bindFoodType(context: Context, tvFoodType: Int, cafeteria: Int) {
    val resId = cafeteriaFoodTypeResId(cafeteria)
    if (resId != null) {
        setViewVisibility(tvFoodType, android.view.View.VISIBLE)
        setTextViewText(tvFoodType, context.getString(resId))
    } else {
        setViewVisibility(tvFoodType, android.view.View.GONE)
    }
}
