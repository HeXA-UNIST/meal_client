package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BapUWidgetMenuTruncationTest {
    @Test
    fun `앞 메뉴를 보존하고 마지막 메뉴만 남은 공간만큼 표시한다`() {
        val result = truncateLastMenuItem(listOf("쌀밥", "아주 긴 메뉴 이름")) {
            it.joinToString("\n").length <= 8
        }

        assertEquals(listOf("쌀밥", "아주 긴…"), result)
    }

    @Test
    fun `생략할 다음 메뉴가 있으면 마지막 메뉴 전체 뒤에도 말줄임표를 붙인다`() {
        assertEquals(listOf("쌀밥", "국…"), truncateLastMenuItem(listOf("쌀밥", "국")) { true })
    }

    @Test
    fun `말줄임표만 들어갈 때는 마지막 메뉴 대신 말줄임표를 표시한다`() {
        assertEquals(listOf("…"), truncateLastMenuItem(listOf("쌀밥")) {
            it.single().length <= 1
        })
    }

    @Test
    fun `앞 메뉴와 말줄임표도 들어가지 않으면 이전 메뉴부터 다시 시도하도록 반환한다`() {
        assertNull(truncateLastMenuItem(listOf("쌀밥", "국")) {
            it.joinToString("\n").length <= 2
        })
    }

    @Test
    fun `이모지 중간을 잘라 잘못된 서로게이트 문자를 만들지 않는다`() {
        val result = truncateLastMenuItem(listOf("🍚🍜국")) {
            it.single().length <= 4
        }

        assertEquals(listOf("🍚…"), result)
    }
}
