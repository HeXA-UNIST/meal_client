package pro.hexa.meal.meal_client

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences  // getWidgetConfigPrefs 에서 사용
import android.util.TypedValue
import android.widget.RemoteViews
import java.util.Calendar

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
 * 표시할 최대 [maxLines]줄로 자른다. 넘치면 마지막 줄에 "..." 추가.
 * 기본값 MAX_MENU_LINES(6)는 공간 계산 없이 쓸 때의 안전 상한.
 */
fun truncateMenu(items: List<String>, maxLines: Int = 6): String {
    if (items.isEmpty()) return "-"
    if (items.size <= maxLines) return items.joinToString("\n")
    val truncated = items.take(maxLines - 1).toMutableList()
    truncated.add("...")
    return truncated.joinToString("\n")
}

/**
 * 메뉴를 두 열로 나눈다. 첫 열: 앞 절반, 둘째 열: 나머지.
 * [maxLines]는 열 하나당 최대 줄 수.
 */
fun splitMenuTwoColumns(items: List<String>, maxLines: Int = 6): Pair<String, String> {
    if (items.isEmpty()) return Pair("-", "")
    val all = if (items.size > maxLines * 2) {
        items.take(maxLines * 2 - 1) + listOf("...")
    } else items
    val half = (all.size + 1) / 2
    val left = all.take(half).joinToString("\n")
    val right = all.drop(half).joinToString("\n")
    return Pair(left, right)
}

// ─── 현재 식사 시간 결정 (MealTimeConfig와 동일한 기준) ───────────────────

/** 0=조식, 1=중식, 2=석식 */
fun currentMealOfDay(): Int {
    val cal = Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Seoul"))
    val h = cal.get(Calendar.HOUR_OF_DAY)
    val m = cal.get(Calendar.MINUTE)
    val mins = h * 60 + m
    return when {
        mins <= 9 * 60 + 20 -> 0   // 아침: ~09:20 (포함)
        mins <= 13 * 60 + 30 -> 1  // 점심: ~13:30 (포함)
        else -> 2                   // 저녁
    }
}

// ─── 식당별 운영 시간 (하드코딩) ────────────────────────────────────────────

data class OperatingPeriod(val startH: Int, val startM: Int, val endH: Int, val endM: Int)

/**
 * cafeteria: CAFE_DORM_KOREAN/HALAL=기숙사, CAFE_STUDENT=학생, CAFE_FACULTY=교직원
 * mealOfDay: 0=조식, 1=중식, 2=석식
 */
fun operatingPeriod(cafeteria: Int, mealOfDay: Int): OperatingPeriod? {
    val cafe = if (cafeteria == CAFE_DORM_HALAL) CAFE_DORM_KOREAN else cafeteria
    return when (cafe) {
        0 -> when (mealOfDay) {
            0 -> OperatingPeriod(8, 0, 9, 20)
            1 -> OperatingPeriod(11, 30, 13, 30)
            2 -> OperatingPeriod(17, 30, 19, 0)
            else -> null
        }
        1 -> when (mealOfDay) {
            1 -> OperatingPeriod(11, 0, 13, 30)
            2 -> OperatingPeriod(17, 0, 19, 0)
            else -> null
        }
        2 -> when (mealOfDay) {
            1 -> OperatingPeriod(11, 0, 13, 0)
            2 -> OperatingPeriod(17, 30, 19, 30)
            else -> null
        }
        else -> null
    }
}

enum class OperatingStatus { BEFORE_OPEN, OPEN, CLOSING_SOON, JUST_CLOSED }

data class OperatingResult(val status: OperatingStatus, val minutesLeft: Int = 0)

fun getOperatingStatus(cafeteria: Int, mealOfDay: Int): OperatingResult {
    val period = operatingPeriod(cafeteria, mealOfDay)
        ?: return OperatingResult(OperatingStatus.BEFORE_OPEN)

    val cal = Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Seoul"))
    val nowMins = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
    val startMins = period.startH * 60 + period.startM
    val endMins = period.endH * 60 + period.endM

    return when {
        nowMins < startMins -> OperatingResult(OperatingStatus.BEFORE_OPEN)
        nowMins <= endMins -> {
            val left = endMins - nowMins
            if (left >= 45) OperatingResult(OperatingStatus.OPEN)
            else OperatingResult(OperatingStatus.CLOSING_SOON, left)
        }
        nowMins <= endMins + 30 -> OperatingResult(OperatingStatus.JUST_CLOSED)
        else -> OperatingResult(OperatingStatus.BEFORE_OPEN)
    }
}

// ─── 위젯 인스턴스별 식당 설정 ───────────────────────────────────────────────

fun loadSingleCafeteria(context: Context, widgetId: Int): Int =
    getWidgetConfigPrefs(context).getInt("config_${widgetId}_cafeteria", CAFE_DORM_KOREAN)

fun saveSingleCafeteria(context: Context, widgetId: Int, cafeteria: Int) =
    getWidgetConfigPrefs(context).edit()
        .putInt("config_${widgetId}_cafeteria", cafeteria)
        .apply()

fun loadDualCafeterias(context: Context, widgetId: Int): Pair<Int, Int> {
    val prefs = getWidgetConfigPrefs(context)
    val c0 = prefs.getInt("config_${widgetId}_cafeteria_0", CAFE_DORM_KOREAN)
    val c1 = prefs.getInt("config_${widgetId}_cafeteria_1", CAFE_STUDENT)
    return Pair(c0, c1)
}

fun saveDualCafeterias(context: Context, widgetId: Int, c0: Int, c1: Int) =
    getWidgetConfigPrefs(context).edit()
        .putInt("config_${widgetId}_cafeteria_0", c0)
        .putInt("config_${widgetId}_cafeteria_1", c1)
        .apply()

fun clearWidgetConfig(context: Context, widgetId: Int) =
    getWidgetConfigPrefs(context).edit()
        .remove("config_${widgetId}_cafeteria")
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

/** AppWidget 옵션에서 세로 모드 최소 높이(dp)를 읽는다. */
fun widgetHeightDp(manager: AppWidgetManager, widgetId: Int): Int {
    val min = manager.getAppWidgetOptions(widgetId)
        .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
    return if (min > 0) min else 150
}

/**
 * 패널 너비(dp)에 따라 메뉴 텍스트 크기(sp)를 결정한다.
 *   ≥ 100dp → 14sp  (표준 이상 크기)
 *   ≥  70dp → 13sp  (소형 셀)
 *   <  70dp → 12sp  (매우 좁은 셀)
 *
 * @param widthDp  위젯 전체 너비(dp)
 * @param columns  가로 패널 수 (단일=1, 좌우 분할=2)
 */
fun calcMenuTextSp(widthDp: Int, columns: Int = 1): Float {
    // 패널 사이 간격: 좌우 각 12dp → 총 24dp
    val panelDp = (widthDp - 28 - 24 * (columns - 1)) / columns
    return when {
        panelDp >= 100 -> 14f
        panelDp >= 70  -> 13f
        else           -> 12f
    }
}

/** 메뉴 sp 에서 kcal sp 를 계산한다 (메뉴보다 2sp 작게, 최소 8sp). */
fun calcKcalTextSp(menuSp: Float): Float = (menuSp - 2f).coerceAtLeast(8f)

/**
 * 패널 높이와 텍스트 크기를 기반으로 칼로리까지 들어갈 최대 메뉴 줄 수를 계산한다.
 *
 * 고정 영역 = 헤더(menuSp) + 마진(6dp) + 마진(2dp) + kcal(kcalSp) + 안전 여유(6dp)
 * 줄 높이   = menuSp + lineSpacingExtra(3sp)  (마지막 줄 포함해서 여유 확보)
 *
 * @param panelHeightDp  패널 하나의 높이(dp). 위젯 루트 패딩(28dp)·행 갭은 호출 측에서 차감 후 전달.
 * @param menuSp         현재 메뉴 텍스트 크기(sp)
 */
fun calcMaxMenuLines(panelHeightDp: Int, menuSp: Float): Int {
    val kcalSp = calcKcalTextSp(menuSp)
    // 고정 영역: 헤더(menuSp) + 마진(6) + 마진(2) + kcal(kcalSp) + 안전 여유(6)
    val fixedDp  = (menuSp + 6 + 2 + kcalSp + 6).toInt()
    val available = panelHeightDp - fixedDp
    if (available <= 0) return 3
    // 줄 높이 = menuSp + lineSpacingExtra(3)  (마지막 줄에도 포함해서 여유 확보)
    val lineHeightDp = menuSp + 3f
    return (available / lineHeightDp).toInt().coerceIn(3, 10)
}

/**
 * RemoteViews 에 메뉴/kcal 텍스트 크기를 일괄 적용한다.
 * SP 단위로 설정하므로 사용자의 글자 크기 접근성 설정도 반영된다.
 */
fun RemoteViews.applyTextSizes(
    menuSp: Float, menuIds: List<Int>,
    kcalSp: Float, kcalIds: List<Int>,
    headerIds: List<Int> = emptyList()
) {
    for (id in menuIds)  setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, menuSp)
    for (id in kcalIds)  setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, kcalSp)
    for (id in headerIds) setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, menuSp)
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
