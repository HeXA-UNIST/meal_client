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
        var dormHalalMenu: List<String>? = null
        var studentMenu: List<String>? = null
        var facultyMenu: List<String>? = null

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
                                dormKoreanMenu = parsed
                            }
                            BapUWidgetContract.Api.MENU_HALAL -> if (dormHalalMenu == null) {
                                dormHalalMenu = parsed
                            }
                        }
                        BapUWidgetContract.Api.CAFETERIA_STUDENT ->
                            if (groupJson.optString("menuType") == BapUWidgetContract.Api.MENU_KOREAN && studentMenu == null) {
                                studentMenu = parsed
                            }
                        BapUWidgetContract.Api.CAFETERIA_FACULTY ->
                            if (groupJson.optString("menuType") == BapUWidgetContract.Api.MENU_KOREAN && facultyMenu == null) {
                                facultyMenu = parsed
                            }
                    }
                }
            }
        }

        return WidgetMealData(
            mealOfDay = mealOfDay.index,
            dormKoreanMenu = dormKoreanMenu ?: emptyList(),
            dormHalalMenu = dormHalalMenu ?: emptyList(),
            studentMenu = studentMenu ?: emptyList(),
            facultyMenu = facultyMenu ?: emptyList(),
        )
    }

    private fun parseRegularMenuGroup(groupJson: JSONObject, languageCode: String): List<String>? {
        val sections = groupJson.getJSONArray("sections")
        val menu = mutableListOf<String>()

        for (i in 0 until sections.length()) {
            val sectionJson = sections.getJSONObject(i)
            if (sectionJson.optString("sectionType") != BapUWidgetContract.Api.SECTION_REGULAR) continue

            val menus = sectionJson.getJSONArray("menus")
            for (j in 0 until menus.length()) {
                val itemJson = menus.getJSONObject(j)
                menu.add(localizedMenuName(itemJson, languageCode))
            }
        }

        if (menu.isEmpty()) return null
        return menu
    }

    private fun localizedMenuName(itemJson: JSONObject, languageCode: String): String {
        val ko = itemJson.getString("ko")
        if (!languageCode.startsWith("en")) return ko

        val en = itemJson.optString("en", "")
        return en.takeIf { it.isNotBlank() } ?: ko
    }
}
