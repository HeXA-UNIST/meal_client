package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Calendar

class BapUWidgetTimeTest {
    @Test
    fun `끼니 경계는 주입된 전환 시각까지 포함한다`() {
        val transitions = WidgetMealTransitionMinutes(
            breakfastEndMinutes = 10 * 60,
            lunchEndMinutes = 14 * 60,
        )

        assertEquals(WidgetMealOfDay.BREAKFAST, BapUWidgetTime.mealOfDayForMinutes(10 * 60, transitions))
        assertEquals(WidgetMealOfDay.LUNCH, BapUWidgetTime.mealOfDayForMinutes(10 * 60 + 1, transitions))
        assertEquals(WidgetMealOfDay.LUNCH, BapUWidgetTime.mealOfDayForMinutes(14 * 60, transitions))
        assertEquals(WidgetMealOfDay.DINNER, BapUWidgetTime.mealOfDayForMinutes(14 * 60 + 1, transitions))
    }

    @Test
    fun `요일은 backend API key로 변환된다`() {
        val cal = Calendar.getInstance(BapUWidgetTime.kstTimeZone)

        cal.set(Calendar.DAY_OF_WEEK, Calendar.MONDAY)
        assertEquals("MON", BapUWidgetTime.dayOfWeekApiKey(cal))
        cal.set(Calendar.DAY_OF_WEEK, Calendar.SUNDAY)
        assertEquals("SUN", BapUWidgetTime.dayOfWeekApiKey(cal))
    }

    @Test
    fun `KST week id는 월요일 자정 기준으로 증가한다`() {
        val sunday = Calendar.getInstance(BapUWidgetTime.kstTimeZone).apply {
            set(2026, Calendar.JUNE, 21, 23, 59, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val monday = Calendar.getInstance(BapUWidgetTime.kstTimeZone).apply {
            set(2026, Calendar.JUNE, 22, 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }

        assertEquals(
            BapUWidgetTime.kstWeekId(sunday.timeInMillis) + 1,
            BapUWidgetTime.kstWeekId(monday.timeInMillis)
        )
    }
}
