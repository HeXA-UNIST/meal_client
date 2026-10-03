package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BapUWidgetLocaleTest {
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
