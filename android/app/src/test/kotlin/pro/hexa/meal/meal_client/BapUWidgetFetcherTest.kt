package pro.hexa.meal.meal_client

import org.junit.Assert.assertEquals
import org.junit.Test

class BapUWidgetFetcherTest {
    @Test
    fun `v2 JSON에서 선택한 요일과 끼니의 REGULAR 메뉴만 위젯 데이터로 파싱한다`() {
        val json = """
            {
              "week": {
                "startDate": "2026-06-15",
                "isCurrentWeek": true,
                "nextWeekStart": null
              },
              "lastUpdated": "2026-06-15T09:00:00+09:00",
              "data": [
                {
                  "cafeteria": "DORMITORY",
                  "meals": [
                    {
                      "date": "2026-06-15",
                      "dayOfWeek": "MON",
                      "timeType": "BREAKFAST",
                      "menusByType": [
                        {
                          "menuType": "KOREAN",
                          "sections": [
                            {
                              "sectionType": "REGULAR",
                              "sectionTitle": null,
                              "calorie": 935,
                              "sectionAllergens": null,
                              "menus": [
                                { "ko": "쌀밥", "en": "Rice", "allergens": [] },
                                { "ko": "황태해장국", "en": "Dried pollack soup", "allergens": [1, 5] }
                              ]
                            },
                            {
                              "sectionType": "CONVENIENCE",
                              "sectionTitle": { "ko": "간편식", "en": "Grab-and-go" },
                              "calorie": 300,
                              "sectionAllergens": [1],
                              "menus": [
                                { "ko": "삼각김밥", "en": "Triangle gimbap", "allergens": null }
                              ]
                            }
                          ]
                        },
                        {
                          "menuType": "HALAL",
                          "sections": [
                            {
                              "sectionType": "REGULAR",
                              "sectionTitle": null,
                              "calorie": 958,
                              "sectionAllergens": null,
                              "menus": [
                                { "ko": "할랄밥", "en": "Halal rice", "allergens": [] }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  "cafeteria": "STUDENT",
                  "meals": [
                    {
                      "date": "2026-06-15",
                      "dayOfWeek": "MON",
                      "timeType": "BREAKFAST",
                      "menusByType": [
                        {
                          "menuType": "KOREAN",
                          "sections": [
                            {
                              "sectionType": "REGULAR",
                              "sectionTitle": null,
                              "calorie": null,
                              "sectionAllergens": null,
                              "menus": [
                                { "ko": "학생식당 조식", "en": null, "allergens": null }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                },
                {
                  "cafeteria": "FACULTY",
                  "meals": [
                    {
                      "date": "2026-06-15",
                      "dayOfWeek": "MON",
                      "timeType": "BREAKFAST",
                      "menusByType": [
                        {
                          "menuType": "KOREAN",
                          "sections": [
                            {
                              "sectionType": "REGULAR",
                              "sectionTitle": null,
                              "calorie": 730,
                              "sectionAllergens": null,
                              "menus": [
                                { "ko": "교직원식당 조식", "en": null, "allergens": null }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
        """.trimIndent()

        val data = BapUWidgetFetcher.parseWidgetMealData(json, "MON", "BREAKFAST", 0)

        assertEquals(listOf("쌀밥", "황태해장국"), data.dormKoreanMenu)
        assertEquals(listOf("할랄밥"), data.dormHalalMenu)
        assertEquals(listOf("학생식당 조식"), data.studentMenu)
        assertEquals(listOf("교직원식당 조식"), data.facultyMenu)
    }

    @Test
    fun `영어 locale에서는 영어 메뉴명을 쓰고 없으면 한국어로 폴백한다`() {
        val json = """
            {
              "week": {
                "startDate": "2026-06-15",
                "isCurrentWeek": true,
                "nextWeekStart": null
              },
              "lastUpdated": "2026-06-15T09:00:00+09:00",
              "data": [
                {
                  "cafeteria": "DORMITORY",
                  "meals": [
                    {
                      "date": "2026-06-15",
                      "dayOfWeek": "MON",
                      "timeType": "BREAKFAST",
                      "menusByType": [
                        {
                          "menuType": "KOREAN",
                          "sections": [
                            {
                              "sectionType": "REGULAR",
                              "sectionTitle": null,
                              "calorie": 935,
                              "sectionAllergens": null,
                              "menus": [
                                { "ko": "쌀밥", "en": "Rice", "allergens": [] },
                                { "ko": "된장국", "en": null, "allergens": [] },
                                { "ko": "김치", "en": "", "allergens": [] }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
        """.trimIndent()

        val data = BapUWidgetFetcher.parseWidgetMealData(
            json,
            "MON",
            "BREAKFAST",
            0,
            languageCode = "en"
        )

        assertEquals(listOf("Rice", "된장국", "김치"), data.dormKoreanMenu)
    }

    @Test
    fun `여러 REGULAR 섹션이 있으면 메뉴를 순서대로 합친다`() {
        val json = """
            {
              "week": {
                "startDate": "2026-06-15",
                "isCurrentWeek": true,
                "nextWeekStart": null
              },
              "lastUpdated": "2026-06-15T09:00:00+09:00",
              "data": [
                {
                  "cafeteria": "DORMITORY",
                  "meals": [
                    {
                      "date": "2026-06-16",
                      "dayOfWeek": "TUE",
                      "timeType": "LUNCH",
                      "menusByType": [
                        {
                          "menuType": "KOREAN",
                          "sections": [
                            {
                              "sectionType": "REGULAR",
                              "sectionTitle": null,
                              "calorie": 700,
                              "sectionAllergens": null,
                              "menus": [
                                { "ko": "쌀밥", "en": "Rice", "allergens": [] }
                              ]
                            },
                            {
                              "sectionType": "REGULAR",
                              "sectionTitle": null,
                              "calorie": 700,
                              "sectionAllergens": null,
                              "menus": [
                                { "ko": "된장국", "en": "Soybean paste soup", "allergens": [] }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
        """.trimIndent()

        val data = BapUWidgetFetcher.parseWidgetMealData(json, "TUE", "LUNCH", 1)

        assertEquals(listOf("쌀밥", "된장국"), data.dormKoreanMenu)
    }

    @Test
    fun `data가 빈 배열이면 모든 메뉴는 빈 목록이다`() {
        val json = """
            {
              "week": {
                "startDate": "2026-06-15",
                "isCurrentWeek": true,
                "nextWeekStart": null
              },
              "lastUpdated": "2026-06-15T09:00:00+09:00",
              "data": []
            }
        """.trimIndent()

        val data = BapUWidgetFetcher.parseWidgetMealData(json, "MON", "BREAKFAST", 0)

        assertEquals(emptyList<String>(), data.dormKoreanMenu)
        assertEquals(emptyList<String>(), data.dormHalalMenu)
        assertEquals(emptyList<String>(), data.studentMenu)
        assertEquals(emptyList<String>(), data.facultyMenu)
    }
}
