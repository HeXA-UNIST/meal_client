package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Test

class BapUWidgetContractTest {
    @Test
    fun `기존 SharedPreferences 식당 저장값과 enum 값은 호환된다`() {
        assertEquals(0, WidgetCafeteria.DORM_KOREAN.prefValue)
        assertEquals(10, WidgetCafeteria.DORM_HALAL.prefValue)
        assertEquals(1, WidgetCafeteria.STUDENT.prefValue)
        assertEquals(2, WidgetCafeteria.FACULTY.prefValue)

        assertEquals(WidgetCafeteria.DORM_KOREAN, WidgetCafeteria.fromPrefValue(0))
        assertEquals(WidgetCafeteria.DORM_HALAL, WidgetCafeteria.fromPrefValue(10))
        assertEquals(WidgetCafeteria.STUDENT, WidgetCafeteria.fromPrefValue(1))
        assertEquals(WidgetCafeteria.FACULTY, WidgetCafeteria.fromPrefValue(2))
    }
}
