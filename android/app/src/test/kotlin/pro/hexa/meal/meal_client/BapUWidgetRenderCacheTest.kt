package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BapUWidgetRenderCacheTest {
    private val inputs = WidgetRenderInputs(
        WidgetMealData(mealOfDay = 0, languageCode = "ko"), 0,
        listOf(160f to 150f), "기본 설정", true,
    )

    @Test
    fun `동일 요청은 생략하되 시스템 요청과 다른 위젯은 다시 그린다`() {
        val cache = BapUWidgetRenderCache()
        var renders = 0
        cache.update(1, inputs, true) { renders++ }
        cache.update(1, inputs.copy(), true) { renders++ }
        assertEquals(1, renders)
        cache.update(1, inputs, false) { renders++ }
        cache.update(2, inputs, true) { renders++ }
        cache.remove(1)
        cache.update(1, inputs, true) { renders++ }
        assertEquals(4, renders)
    }

    @Test
    fun `실패한 갱신과 새 프로세스에서는 동일 입력도 재시도한다`() {
        val cache = BapUWidgetRenderCache()
        cache.update(1, inputs, true) {}
        assertThrows(IllegalStateException::class.java) {
            cache.update(1, inputs, false) { error("런처 갱신 실패") }
        }
        var renders = 0
        cache.update(1, inputs, true) { renders++ }
        BapUWidgetRenderCache().update(1, inputs, true) { renders++ }
        assertEquals(2, renders)
    }
}
