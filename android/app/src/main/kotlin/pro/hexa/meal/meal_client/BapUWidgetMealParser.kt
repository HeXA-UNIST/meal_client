package pro.hexa.meal.meal_client

import org.json.JSONObject

object BapUWidgetMealParser {
    fun parse(
        json: String,
        dayType: String,
        mealType: String,
        mealOfDay: WidgetMealOfDay,
        languageCode: String = "ko"
    ): WidgetMealData {
        val root = JSONObject(json)
        val cafeterias = root.getJSONArray("data")
        var dormKoreanMenu: List<String>? = null
        var dormKoreanKcal: Int? = null
        var dormHalalMenu: List<String>? = null
        var dormHalalKcal: Int? = null
        var studentMenu: List<String>? = null
        var studentKcal: Int? = null
        var facultyMenu: List<String>? = null
        var facultyKcal: Int? = null

        for (i in 0 until cafeterias.length()) {
            val cafeteriaJson = cafeterias.getJSONObject(i)
            val cafeteria = cafeteriaJson.optString("cafeteria")
            val meals = cafeteriaJson.getJSONArray("meals")

            for (j in 0 until meals.length()) {
                val mealJson = meals.getJSONObject(j)
                if (mealJson.optString("dayOfWeek") != dayType) continue
                if (mealJson.optString("timeType") != mealType) continue

                val menuGroups = mealJson.getJSONArray("menusByType")
                for (k in 0 until menuGroups.length()) {
                    val groupJson = menuGroups.getJSONObject(k)
                    val parsed = parseRegularMenuGroup(groupJson, languageCode) ?: continue

                    when (cafeteria) {
                        BapUWidgetContract.Api.CAFETERIA_DORMITORY -> when (groupJson.optString("menuType")) {
                            BapUWidgetContract.Api.MENU_KOREAN -> if (dormKoreanMenu == null) {
                                dormKoreanMenu = parsed.menu
                                dormKoreanKcal = parsed.kcal
                            }
                            BapUWidgetContract.Api.MENU_HALAL -> if (dormHalalMenu == null) {
                                dormHalalMenu = parsed.menu
                                dormHalalKcal = parsed.kcal
                            }
                        }
                        BapUWidgetContract.Api.CAFETERIA_STUDENT ->
                            if (groupJson.optString("menuType") == BapUWidgetContract.Api.MENU_KOREAN && studentMenu == null) {
                                studentMenu = parsed.menu
                                studentKcal = parsed.kcal
                            }
                        BapUWidgetContract.Api.CAFETERIA_FACULTY ->
                            if (groupJson.optString("menuType") == BapUWidgetContract.Api.MENU_KOREAN && facultyMenu == null) {
                                facultyMenu = parsed.menu
                                facultyKcal = parsed.kcal
                            }
                    }
                }
            }
        }

        return WidgetMealData(
            mealOfDay = mealOfDay.index,
            dormKoreanMenu = dormKoreanMenu ?: emptyList(),
            dormKoreanKcal = dormKoreanKcal,
            dormHalalMenu = dormHalalMenu ?: emptyList(),
            dormHalalKcal = dormHalalKcal,
            studentMenu = studentMenu ?: emptyList(),
            studentKcal = studentKcal,
            facultyMenu = facultyMenu ?: emptyList(),
            facultyKcal = facultyKcal,
        )
    }

    private data class ParsedMenuGroup(val menu: List<String>, val kcal: Int?)

    private fun parseRegularMenuGroup(groupJson: JSONObject, languageCode: String): ParsedMenuGroup? {
        val sections = groupJson.getJSONArray("sections")
        val menu = mutableListOf<String>()
        val calories = mutableListOf<Int>()
        var regularSectionCount = 0

        for (i in 0 until sections.length()) {
            val sectionJson = sections.getJSONObject(i)
            if (sectionJson.optString("sectionType") != BapUWidgetContract.Api.SECTION_REGULAR) continue

            regularSectionCount += 1
            if (!sectionJson.isNull("calorie")) {
                calories.add(sectionJson.getInt("calorie"))
            }

            val menus = sectionJson.getJSONArray("menus")
            for (j in 0 until menus.length()) {
                val itemJson = menus.getJSONObject(j)
                menu.add(localizedMenuName(itemJson, languageCode))
            }
        }

        if (menu.isEmpty()) return null
        return ParsedMenuGroup(
            menu = menu,
            kcal = if (regularSectionCount == 1 && calories.size == 1) calories.first() else null
        )
    }

    private fun localizedMenuName(itemJson: JSONObject, languageCode: String): String {
        val ko = itemJson.getString("ko")
        if (!languageCode.startsWith("en")) return ko

        val en = itemJson.optString("en", "")
        return en.takeIf { it.isNotBlank() } ?: ko
    }
}
