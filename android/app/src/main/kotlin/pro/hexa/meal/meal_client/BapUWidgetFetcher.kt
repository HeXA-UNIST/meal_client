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
)

object BapUWidgetFetcher {
    fun fetch(context: Context): WidgetMealData? =
        BapUWidgetMealRepository.fetch(context)

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
