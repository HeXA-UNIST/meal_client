package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Calendar

class BapUWidgetScheduleManagerTest {
    private val transitions = WidgetMealTransitionMinutes(
        breakfastEndMinutes = 10 * 60,
        lunchEndMinutes = 14 * 60,
    )

    @Test
    fun `끼니 전환 경계는 info json에서 계산된 종료 시각을 사용한다`() {
        assertEquals(
            listOf(0, 10 * 60 + 1, 14 * 60 + 1),
            BapUWidgetScheduleManager.allBoundaryMinutesToday(emptyList(), transitions)
        )
    }

    @Test
    fun `info 기반 운영시간 경계와 동적 끼니 경계를 함께 예약한다`() {
        val boundaries = BapUWidgetScheduleManager.allBoundaryMinutesToday(
            listOf(OperatingPeriod(11, 30, 13, 30)),
            transitions,
        )

        assertEquals(listOf(0, 10 * 60 + 1, 11 * 60 + 30, 12 * 60 + 45, 14 * 60 + 1), boundaries)
    }

    @Test
    fun `마감 임박 구간에서는 다음 1분에 다시 예약한다`() {
        val now = Calendar.getInstance(BapUWidgetTime.kstTimeZone).apply {
            set(2026, Calendar.JUNE, 15, 12, 50, 10)
            set(Calendar.MILLISECOND, 500)
        }

        assertEquals(
            49_500L,
            BapUWidgetScheduleManager.millisUntilNextWake(
                now,
                listOf(OperatingPeriod(11, 30, 13, 30)),
                transitions,
            )
        )
    }

    @Test
    fun `마지막 끼니 경계 이후에는 다음날 자정에 다시 예약한다`() {
        val now = Calendar.getInstance(BapUWidgetTime.kstTimeZone).apply {
            set(2026, Calendar.JUNE, 15, 13, 31, 10)
            set(Calendar.MILLISECOND, 500)
        }

        assertEquals(
            (29 * 60 + 49) * 1000L + 500L,
            BapUWidgetScheduleManager.millisUntilNextWake(now, emptyList(), transitions)
        )
    }
}
