package pro.hexa.meal.meal_client

object BapUWidgetContract {
    const val MEAL_CACHE_FILE = "meal.json"
    const val INFO_CACHE_FILE = "info.json"
    const val KST_ZONE_ID = "Asia/Seoul"

    object Api {
        const val CAFETERIA_DORMITORY = "DORMITORY"
        const val CAFETERIA_STUDENT = "STUDENT"
        const val CAFETERIA_FACULTY = "FACULTY"

        const val TIME_BREAKFAST = "BREAKFAST"
        const val TIME_LUNCH = "LUNCH"
        const val TIME_DINNER = "DINNER"

        const val MENU_KOREAN = "KOREAN"
        const val MENU_HALAL = "HALAL"
        const val SECTION_REGULAR = "REGULAR"

        const val DAY_MONDAY = "MON"
        const val DAY_TUESDAY = "TUE"
        const val DAY_WEDNESDAY = "WED"
        const val DAY_THURSDAY = "THU"
        const val DAY_FRIDAY = "FRI"
        const val DAY_SATURDAY = "SAT"
        const val DAY_SUNDAY = "SUN"
    }

    object MealTime {
        const val CLOSING_SOON_THRESHOLD_MINUTES = 45
        const val JUST_CLOSED_DURATION_MINUTES = 30
    }
}

enum class WidgetCafeteria(val prefValue: Int) {
    DORM_KOREAN(0),
    STUDENT(1),
    FACULTY(2),
    DORM_HALAL(10);

    companion object {
        fun fromPrefValue(value: Int): WidgetCafeteria =
            values().firstOrNull { it.prefValue == value } ?: DORM_KOREAN
    }
}

enum class WidgetMealOfDay(val index: Int, val apiKey: String) {
    BREAKFAST(0, BapUWidgetContract.Api.TIME_BREAKFAST),
    LUNCH(1, BapUWidgetContract.Api.TIME_LUNCH),
    DINNER(2, BapUWidgetContract.Api.TIME_DINNER);

    companion object {
        fun fromIndex(index: Int): WidgetMealOfDay =
            values().firstOrNull { it.index == index } ?: BREAKFAST
    }
}
