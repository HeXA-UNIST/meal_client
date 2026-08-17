package pro.hexa.meal.meal_client

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BapUWidgetMealRepositoryTest {
    @Test
    fun `다음 주 payload는 일요일 mtime과 무관하게 월요일에 선택된다`() {
        withCaches(rawMeal("2026-08-17", "previous"), rawMeal("2026-08-24", "next")) { canonical, next ->
            val data = BapUWidgetMealRepository.selectMealData(
                canonical, next, "2026-08-24", "MON", WidgetMealOfDay.BREAKFAST,
            )

            assertEquals(listOf("next"), data?.dormKoreanMenu)
        }
    }

    @Test
    fun `같은 주 파일 둘은 canonical meal json을 우선한다`() {
        withCaches(rawMeal("2026-08-24", "canonical"), rawMeal("2026-08-24", "next")) { canonical, next ->
            val data = BapUWidgetMealRepository.selectMealData(
                canonical, next, "2026-08-24", "MON", WidgetMealOfDay.BREAKFAST,
            )

            assertEquals(listOf("canonical"), data?.dormKoreanMenu)
        }
    }

    @Test
    fun `선택한 화요일 끼니가 손상된 canonical은 next cache로 폴백한다`() {
        val corruptTuesday = """
            {"week":{"startDate":"2026-08-24"},"data":[{"cafeteria":"DORMITORY","meals":[
              {"dayOfWeek":"TUE","timeType":"LUNCH","menusByType":"broken"}
            ]}]}
        """.trimIndent()
        withCaches(corruptTuesday, rawMeal("2026-08-24", "next", "TUE", "LUNCH")) { canonical, next ->
            val data = BapUWidgetMealRepository.selectMealData(
                canonical, next, "2026-08-24", "TUE", WidgetMealOfDay.LUNCH,
            )

            assertEquals(listOf("next"), data?.dormKoreanMenu)
        }
    }

    @Test
    fun `일치하는 payload가 없으면 이전 주 메뉴로 폴백하지 않는다`() {
        withCaches(rawMeal("2026-08-17", "previous"), null) { canonical, next ->
            assertNull(
                BapUWidgetMealRepository.selectMealData(
                    canonical, next, "2026-08-24", "MON", WidgetMealOfDay.BREAKFAST,
                ),
            )
        }
    }

    private fun withCaches(
        canonicalRaw: String,
        nextRaw: String?,
        action: (File, File) -> Unit,
    ) {
        val directory = createTempDir(prefix = "bapu-widget-")
        try {
            val canonical = File(directory, BapUWidgetContract.MEAL_CACHE_FILE).apply {
                writeText(canonicalRaw)
            }
            val next = File(directory, BapUWidgetContract.NEXT_MEAL_CACHE_FILE).apply {
                if (nextRaw != null) writeText(nextRaw)
            }
            action(canonical, next)
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun rawMeal(
        weekStart: String,
        menu: String,
        day: String = "MON",
        time: String = "BREAKFAST",
    ) = """
        {"week":{"startDate":"$weekStart"},"data":[{"cafeteria":"DORMITORY","meals":[{
          "dayOfWeek":"$day","timeType":"$time","menusByType":[{"menuType":"KOREAN","sections":[{
            "sectionType":"REGULAR","menus":[{"ko":"$menu","en":null}]
          }]}]
        }]}]}
    """.trimIndent()
}
