package pro.hexa.meal.meal_client

import android.content.Context

data class WidgetMealData(
    val mealOfDay: Int,
    val dormKoreanMenu: List<String> = emptyList(),
    val dormKoreanKcal: Int? = null,
    val dormHalalMenu: List<String> = emptyList(),
    val dormHalalKcal: Int? = null,
    val studentMenu: List<String> = emptyList(),
    val studentKcal: Int? = null,
    val facultyMenu: List<String> = emptyList(),
    val facultyKcal: Int? = null,
    val errorMessageResId: Int? = null,
) {
    val isError: Boolean
        get() = errorMessageResId != null

    companion object {
        fun empty(mealOfDay: WidgetMealOfDay): WidgetMealData =
            WidgetMealData(mealOfDay = mealOfDay.index)

        fun error(): WidgetMealData =
            WidgetMealData(mealOfDay = -1, errorMessageResId = R.string.widget_data_error)
    }
}

object BapUWidgetFetcher {
    fun fetch(context: Context): WidgetMealData =
        runCatching { BapUWidgetMealRepository.fetch(context) }
            .getOrElse { WidgetMealData.error() }

    internal fun parseWidgetMealData(
        json: String,
        dayType: String,
        mealType: String,
        mealOfDay: Int,
        languageCode: String = "ko"
    ): WidgetMealData =
        BapUWidgetMealParser.parse(
            json = json,
            dayType = dayType,
            mealType = mealType,
            mealOfDay = WidgetMealOfDay.fromIndex(mealOfDay),
            languageCode = languageCode
        )
}

fun WidgetMealData.mealLabel(context: Context): String =
    if (isError) context.getString(R.string.widget_error_title) else context.getString(mealOfDayResId(mealOfDay))

fun WidgetMealData.menuItems(context: Context, cafeteria: Int): List<String> =
    errorMessageResId?.let { listOf(context.getString(it)) } ?: menuFromData(this, cafeteria)

/**
 * 데이터 자체를 못 불러온 경우(isError, mealOfDay=-1이라 실제 조회가 무의미함)도
 * 상태 줄을 숨기지 않고 "-"로 표시한다 — 메뉴 쪽은 이미 에러 문구를 보여주므로 일관되게.
 */
fun WidgetMealData.operatingStatus(context: Context, cafeteria: Int): Pair<Int, String> =
    if (isError) Pair(context.getColor(R.color.widget_status_closed), context.getString(R.string.widget_no_menu))
    else operatingStatusDisplay(context, cafeteria, mealOfDay)

fun menuFromData(data: WidgetMealData, cafeteria: Int): List<String> = when (WidgetCafeteria.fromPrefValue(cafeteria)) {
    WidgetCafeteria.DORM_KOREAN -> data.dormKoreanMenu
    WidgetCafeteria.DORM_HALAL -> data.dormHalalMenu
    WidgetCafeteria.STUDENT -> data.studentMenu
    WidgetCafeteria.FACULTY -> data.facultyMenu
}

fun kcalFromData(data: WidgetMealData, cafeteria: Int): Int? = when (WidgetCafeteria.fromPrefValue(cafeteria)) {
    WidgetCafeteria.DORM_KOREAN -> data.dormKoreanKcal
    WidgetCafeteria.DORM_HALAL -> data.dormHalalKcal
    WidgetCafeteria.STUDENT -> data.studentKcal
    WidgetCafeteria.FACULTY -> data.facultyKcal
}
