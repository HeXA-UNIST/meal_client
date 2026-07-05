package pro.hexa.meal.meal_client

import java.util.Calendar
import java.util.GregorianCalendar
import java.util.TimeZone

object BapUWidgetTime {
    val kstTimeZone: TimeZone = TimeZone.getTimeZone(BapUWidgetContract.KST_ZONE_ID)

    private val utcTimeZone: TimeZone = TimeZone.getTimeZone("UTC")
    private const val KST_OFFSET_MS = 9L * 60 * 60 * 1000
    private const val WEEK_MS = 7L * 24 * 60 * 60 * 1000
    private val weekEpochMs = GregorianCalendar(utcTimeZone).apply {
        set(1970, Calendar.JANUARY, 5, 0, 0, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    fun mealOfDayForMinutes(
        nowMinutes: Int,
        transitions: WidgetMealTransitionMinutes,
    ): WidgetMealOfDay = when {
        nowMinutes <= transitions.breakfastEndMinutes -> WidgetMealOfDay.BREAKFAST
        nowMinutes <= transitions.lunchEndMinutes -> WidgetMealOfDay.LUNCH
        else -> WidgetMealOfDay.DINNER
    }

    fun kstWeekId(ms: Long): Long =
        (ms + KST_OFFSET_MS - weekEpochMs) / WEEK_MS

    fun dayOfWeekApiKey(calendar: Calendar): String = when (calendar.get(Calendar.DAY_OF_WEEK)) {
        Calendar.MONDAY -> BapUWidgetContract.Api.DAY_MONDAY
        Calendar.TUESDAY -> BapUWidgetContract.Api.DAY_TUESDAY
        Calendar.WEDNESDAY -> BapUWidgetContract.Api.DAY_WEDNESDAY
        Calendar.THURSDAY -> BapUWidgetContract.Api.DAY_THURSDAY
        Calendar.FRIDAY -> BapUWidgetContract.Api.DAY_FRIDAY
        Calendar.SATURDAY -> BapUWidgetContract.Api.DAY_SATURDAY
        Calendar.SUNDAY -> BapUWidgetContract.Api.DAY_SUNDAY
        else -> BapUWidgetContract.Api.DAY_MONDAY
    }
}

data class WidgetMealTransitionMinutes(
    val breakfastEndMinutes: Int,
    val lunchEndMinutes: Int,
)
