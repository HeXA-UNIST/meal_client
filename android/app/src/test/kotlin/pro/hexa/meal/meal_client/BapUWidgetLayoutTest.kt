package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BapUWidgetLayoutTest {
    @Test
    fun `4칸 너비부터 메뉴를 2열로 표시한다`() {
        assertFalse(usesTwoColumnMenu(249))
        assertTrue(usesTwoColumnMenu(250))
    }

    @Test
    fun `메뉴 순서를 유지하면서 두 열을 균등하게 나눈다`() {
        val (left, right) = splitMenuItemsIntoColumns(listOf("1", "2", "3", "4", "5"))

        assertEquals(listOf("1", "2", "3"), left)
        assertEquals(listOf("4", "5"), right)
    }

    @Test
    fun `말줄임표는 마지막 표시 메뉴와 같은 줄에 붙인다`() {
        assertEquals(
            listOf("1", "2", "3…"),
            appendInlineMenuEllipsis(listOf("1", "2", "3"))
        )
    }
}
