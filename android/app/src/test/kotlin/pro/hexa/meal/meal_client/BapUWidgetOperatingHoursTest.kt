package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Calendar

class BapUWidgetOperatingHoursTest {
    @Test
    fun `info json 운영시간으로 현재 운영 상태를 계산한다`() {
        val hours = BapUWidgetOperatingHours.parseRawInfo(sampleInfoJson())
        val now = kstCalendar(Calendar.MONDAY, 12, 0)

        val dormStatus = BapUWidgetOperatingHours.statusFor(hours, CAFE_DORM_KOREAN, 1, now)
        val halalStatus = BapUWidgetOperatingHours.statusFor(hours, CAFE_DORM_HALAL, 1, now)
        val facultyStatus = BapUWidgetOperatingHours.statusFor(hours, CAFE_FACULTY, 1, now)

        assertEquals(OperatingStatus.OPEN, dormStatus?.status)
        assertEquals(OperatingStatus.OPEN, halalStatus?.status)
        assertEquals(OperatingStatus.CLOSING_SOON, facultyStatus?.status)
    }

    @Test
    fun `종료 정확히 45분 전부터 마감 임박 상태다`() {
        val hours = BapUWidgetOperatingHours.parseRawInfo(sampleInfoJson())

        val status = BapUWidgetOperatingHours.statusFor(
            hours,
            CAFE_FACULTY,
            WidgetMealOfDay.LUNCH.index,
            kstCalendar(Calendar.MONDAY, 11, 45),
        )

        assertEquals(OperatingStatus.CLOSING_SOON, status?.status)
    }

    @Test
    fun `주말은 KST 날짜 기준 weekend 운영시간을 사용한다`() {
        val hours = BapUWidgetOperatingHours.parseRawInfo(sampleInfoJson())
        val now = kstCalendar(2026, Calendar.JUNE, 21, 10, 10)

        val status = BapUWidgetOperatingHours.statusFor(hours, CAFE_DORM_KOREAN, 0, now)

        assertEquals(OperatingStatus.OPEN, status?.status)
    }

    @Test
    fun `선택 식당이 먼저 닫히면 다음 전역 끼니까지 운영 종료를 유지한다`() {
        val hours = BapUWidgetOperatingHours.parseRawInfo(sampleInfoJson())!!
        val now = kstCalendar(Calendar.MONDAY, 13, 0)

        val status = BapUWidgetOperatingHours.statusFor(hours, CAFE_FACULTY, WidgetMealOfDay.LUNCH.index, now)

        assertEquals(WidgetMealOfDay.LUNCH, BapUWidgetOperatingHours.currentMealOfDay(hours, now))
        assertEquals(OperatingStatus.CLOSED, status?.status)
    }

    @Test
    fun `cache 오류는 상태를 숨기고 식당 운영시간이 없으면 미운영을 반환한다`() {
        assertNull(BapUWidgetOperatingHours.parseRawInfo(""))
        assertNull(BapUWidgetOperatingHours.parseRawInfo("{"))

        val hours = BapUWidgetOperatingHours.parseRawInfo(sampleInfoJson())
        assertEquals(
            OperatingStatus.NO_SERVICE,
            BapUWidgetOperatingHours.statusFor(hours, CAFE_STUDENT, 0, kstCalendar(Calendar.MONDAY, 8, 30))?.status,
        )
        assertNull(BapUWidgetOperatingHours.statusFor(null, CAFE_DORM_KOREAN, 1, kstCalendar(Calendar.MONDAY, 12, 0)))
    }

    @Test
    fun `scheduler periods는 info json 기반 오늘 운영시간 목록을 반환한다`() {
        val hours = BapUWidgetOperatingHours.parseRawInfo(sampleInfoJson())
        val periods = BapUWidgetOperatingHours.periodsForToday(hours, kstCalendar(Calendar.MONDAY, 12, 0))

        assertEquals(
            listOf(
                OperatingPeriod(8, 0, 9, 20),
                OperatingPeriod(11, 0, 13, 30),
                OperatingPeriod(11, 30, 12, 30),
                OperatingPeriod(11, 30, 13, 30),
                OperatingPeriod(17, 0, 19, 0),
                OperatingPeriod(17, 30, 19, 0),
                OperatingPeriod(17, 30, 19, 30),
            ),
            periods
        )
    }

    @Test
    fun `끼니 전환 경계는 오늘 식당별 가장 늦은 종료 시각으로 계산한다`() {
        val hours = BapUWidgetOperatingHours.parseRawInfo(sampleInfoJson())!!
        val transitions = BapUWidgetOperatingHours.mealTransitionsForToday(
            hours,
            kstCalendar(Calendar.MONDAY, 12, 0),
        )

        assertEquals(9 * 60 + 20, transitions.breakfastEndMinutes)
        assertEquals(13 * 60 + 30, transitions.lunchEndMinutes)
        assertEquals(
            WidgetMealOfDay.LUNCH,
            BapUWidgetOperatingHours.currentMealOfDay(hours, kstCalendar(Calendar.MONDAY, 9, 21))
        )
    }

    @Test(expected = WidgetInfoCacheException::class)
    fun `끼니 전환 계산에 필요한 운영시간이 없으면 실패한다`() {
        val hours = BapUWidgetOperatingHours.parseRawInfo("""
            {
              "operatingHours": {
                "weekday": {
                  "dormitory": {
                    "breakfast": { "start": "08:00", "end": "09:20" }
                  }
                },
                "weekend": {}
              }
            }
        """.trimIndent())!!

        BapUWidgetOperatingHours.mealTransitionsForToday(hours, kstCalendar(Calendar.MONDAY, 8, 0))
    }

    private fun kstCalendar(dayOfWeek: Int, hour: Int, minute: Int): Calendar =
        Calendar.getInstance(BapUWidgetTime.kstTimeZone).apply {
            set(2026, Calendar.JUNE, 15, hour, minute, 0)
            set(Calendar.DAY_OF_WEEK, dayOfWeek)
            set(Calendar.MILLISECOND, 0)
        }

    private fun kstCalendar(year: Int, month: Int, day: Int, hour: Int, minute: Int): Calendar =
        Calendar.getInstance(BapUWidgetTime.kstTimeZone).apply {
            set(year, month, day, hour, minute, 0)
            set(Calendar.MILLISECOND, 0)
        }

    private fun sampleInfoJson(): String = """
        {
          "announcement": null,
          "operatingHours": {
            "weekday": {
              "dormitory": {
                "breakfast": { "start": "08:00", "end": "09:20" },
                "lunch": { "start": "11:30", "end": "13:30" },
                "dinner": { "start": "17:30", "end": "19:00" }
              },
              "student": {
                "lunch": { "start": "11:00", "end": "13:30" },
                "dinner": { "start": "17:00", "end": "19:00" }
              },
              "faculty": {
                "lunch": { "start": "11:30", "end": "12:30" },
                "dinner": { "start": "17:30", "end": "19:30" }
              }
            },
            "weekend": {
              "dormitory": {
                "breakfast": { "start": "10:00", "end": "11:00" },
                "lunch": { "start": "12:00", "end": "13:00" },
                "dinner": { "start": "17:00", "end": "18:00" }
              },
              "student": {},
              "faculty": {}
            }
          }
        }
    """.trimIndent()
}
