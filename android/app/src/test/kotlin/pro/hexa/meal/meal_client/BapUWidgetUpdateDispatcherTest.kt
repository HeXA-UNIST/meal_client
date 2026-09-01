package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class BapUWidgetUpdateDispatcherTest {
    @Test
    fun `일부 위젯 갱신이 실패해도 나머지를 모두 시도하고 실패를 반환한다`() {
        val attempted = mutableListOf<Int>()
        val failure = IllegalStateException("launcher failure")

        val failures = BapUWidgetUpdateDispatcher.updateBestEffort(intArrayOf(11, 22, 33)) { id ->
            attempted += id
            if (id == 22) throw failure
        }

        assertEquals(listOf(11, 22, 33), attempted)
        assertEquals(listOf(22), failures.map { it.widgetId })
        assertSame(failure, failures.single().cause)
    }
}
