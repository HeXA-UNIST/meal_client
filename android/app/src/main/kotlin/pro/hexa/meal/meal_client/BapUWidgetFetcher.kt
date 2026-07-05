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

fun WidgetMealData.operatingStatus(context: Context, cafeteria: Int): Pair<Int, String>? =
    if (isError) null else operatingStatusDisplay(context, cafeteria, mealOfDay)

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
