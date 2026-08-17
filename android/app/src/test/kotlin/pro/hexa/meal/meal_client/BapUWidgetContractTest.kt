package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Test

class BapUWidgetContractTest {
    @Test
    fun `위젯 cache 파일명과 API enum literal은 Dart 및 backend 계약과 일치한다`() {
        assertEquals("meal.json", BapUWidgetContract.MEAL_CACHE_FILE)
        assertEquals("meal-next.json", BapUWidgetContract.NEXT_MEAL_CACHE_FILE)
        assertEquals("info.json", BapUWidgetContract.INFO_CACHE_FILE)
        assertEquals("Asia/Seoul", BapUWidgetContract.KST_ZONE_ID)

        assertEquals("DORMITORY", BapUWidgetContract.Api.CAFETERIA_DORMITORY)
        assertEquals("STUDENT", BapUWidgetContract.Api.CAFETERIA_STUDENT)
        assertEquals("FACULTY", BapUWidgetContract.Api.CAFETERIA_FACULTY)
        assertEquals("BREAKFAST", WidgetMealOfDay.BREAKFAST.apiKey)
        assertEquals("LUNCH", WidgetMealOfDay.LUNCH.apiKey)
        assertEquals("DINNER", WidgetMealOfDay.DINNER.apiKey)
        assertEquals("REGULAR", BapUWidgetContract.Api.SECTION_REGULAR)
    }

    @Test
    fun `기존 SharedPreferences 식당 저장값과 enum 값은 호환된다`() {
        assertEquals(0, WidgetCafeteria.DORM_KOREAN.prefValue)
        assertEquals(10, WidgetCafeteria.DORM_HALAL.prefValue)
        assertEquals(1, WidgetCafeteria.STUDENT.prefValue)
        assertEquals(2, WidgetCafeteria.FACULTY.prefValue)

        assertEquals(WidgetCafeteria.DORM_KOREAN, WidgetCafeteria.fromPrefValue(CAFE_DORM_KOREAN))
        assertEquals(WidgetCafeteria.DORM_HALAL, WidgetCafeteria.fromPrefValue(CAFE_DORM_HALAL))
        assertEquals(WidgetCafeteria.STUDENT, WidgetCafeteria.fromPrefValue(CAFE_STUDENT))
        assertEquals(WidgetCafeteria.FACULTY, WidgetCafeteria.fromPrefValue(CAFE_FACULTY))
    }
}
