package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.util.Locale

class BapUWidgetLocaleTest {
    @Test
    fun `최초 언어는 시스템 목록의 첫 지원 언어이며 없으면 영어다`() {
        val cases = listOf(
            listOf("en-US", "ko-KR") to "en",
            listOf("ja-JP", "ko-KR", "en-US") to "ko",
            listOf("ja-JP", "en-GB", "ko-KR") to "en",
            listOf("ja-JP") to "en",
            emptyList<String>() to "en",
        )
        for ((tags, expected) in cases) {
            assertEquals(
                expected,
                BapUWidgetMealRepository.resolveInitialLanguageCode(tags.map { Locale.forLanguageTag(it) }),
            )
        }
    }

    @Test
    fun `저장된 지원 언어만 위젯 언어로 사용한다`() {
        assertEquals("ko", BapUWidgetMealRepository.requireSavedLanguageCode("ko"))
        assertEquals("en", BapUWidgetMealRepository.requireSavedLanguageCode("en"))
    }

    @Test
    fun `저장 언어 누락과 잘못된 값은 시스템 언어로 대체하지 않는다`() {
        for (code in listOf(null, "", "ja", "en-US")) {
            assertThrows(IllegalStateException::class.java) {
                BapUWidgetMealRepository.requireSavedLanguageCode(code)
            }
        }
    }
}
