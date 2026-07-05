package pro.hexa.meal.meal_client

import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

data class WidgetMealData(
    val mealOfDay: Int,
    val dormKoreanMenu: List<String> = emptyList(),
    val dormKoreanKcal: Int? = null,
    val dormHalalMenu: List<String> = emptyList(),
    val dormHalalKcal: Int? = null,
    val studentMenu: List<String> = emptyList(),
    val studentKcal: Int? = null,
    val facultyMenu: List<String> = emptyList(),
    val facultyKcal: Int? = null,
)

object BapUWidgetFetcher {
    private const val MEAL_CACHE_FILE = "meal.json"
    // Keep this URL synchronized with ApiConstants.mealEndpoint in Dart.
    private const val API_URL = "https://meal.hexa.pro/v2/menu"
    private val KST = TimeZone.getTimeZone("Asia/Seoul")
    private val UTC = TimeZone.getTimeZone("UTC")
    private const val KST_OFFSET_MS = 9L * 60 * 60 * 1000
    private const val WEEK_MS = 7L * 24 * 60 * 60 * 1000
    private val WEEK_EPOCH_MS = GregorianCalendar(UTC).apply {
        set(1970, Calendar.JANUARY, 5, 0, 0, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis
    private val DAY_TYPES = mapOf(
        Calendar.MONDAY to "MON", Calendar.TUESDAY to "TUE",
        Calendar.WEDNESDAY to "WED", Calendar.THURSDAY to "THU",
        Calendar.FRIDAY to "FRI", Calendar.SATURDAY to "SAT",
        Calendar.SUNDAY to "SUN"
    )
    private val MEAL_TYPES = arrayOf("BREAKFAST", "LUNCH", "DINNER")

    fun fetch(context: Context? = null): WidgetMealData? = try {
        val mealOfDay = currentMealOfDay()
        val mealType = MEAL_TYPES[mealOfDay]
        val cal = Calendar.getInstance(KST)
        val dayType = DAY_TYPES[cal.get(Calendar.DAY_OF_WEEK)] ?: return null
        val languageCode = currentLanguageCode(context)
        loadFromFreshCache(context, dayType, mealType, mealOfDay, languageCode)
            ?: fetchFromNetwork(context, dayType, mealType, mealOfDay, languageCode)
    } catch (e: Exception) {
        null
    }

    private fun loadFromFreshCache(
        context: Context?,
        dayType: String,
        mealType: String,
        mealOfDay: Int,
        languageCode: String
    ): WidgetMealData? {
        if (context == null) return null
        return try {
            val file = File(context.filesDir, MEAL_CACHE_FILE)
            if (!file.isFile || !hasFreshMealCache(file.lastModified())) return null
            parseWidgetMealData(file.readText(Charsets.UTF_8), dayType, mealType, mealOfDay, languageCode)
        } catch (e: Exception) {
            null
        }
    }

    private fun fetchFromNetwork(
        context: Context?,
        dayType: String,
        mealType: String,
        mealOfDay: Int,
        languageCode: String
    ): WidgetMealData {
        val json = httpGet(API_URL)
        val data = parseWidgetMealData(json, dayType, mealType, mealOfDay, languageCode)
        writeCache(context, json)
        return data
    }

    private fun hasFreshMealCache(lastModifiedMs: Long): Boolean =
        kstWeekId(lastModifiedMs) == kstWeekId(System.currentTimeMillis())

    private fun kstWeekId(ms: Long): Long =
        (ms + KST_OFFSET_MS - WEEK_EPOCH_MS) / WEEK_MS

    internal fun parseWidgetMealData(
        json: String,
        dayType: String,
        mealType: String,
        mealOfDay: Int,
        languageCode: String = "ko"
    ): WidgetMealData {
        val root = JSONObject(json)
        val cafeterias = root.getJSONArray("data")
        var dormKoreanMenu: List<String>? = null; var dormKoreanKcal: Int? = null
        var dormHalalMenu: List<String>? = null;  var dormHalalKcal: Int? = null
        var studentMenu: List<String>? = null;    var studentKcal: Int? = null
        var facultyMenu: List<String>? = null;    var facultyKcal: Int? = null

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
                        "DORMITORY" -> when (groupJson.optString("menuType")) {
                            "KOREAN" -> if (dormKoreanMenu == null) {
                                dormKoreanMenu = parsed.menu
                                dormKoreanKcal = parsed.kcal
                            }
                            "HALAL" -> if (dormHalalMenu == null) {
                                dormHalalMenu = parsed.menu
                                dormHalalKcal = parsed.kcal
                            }
                        }
                        "STUDENT" -> if (groupJson.optString("menuType") == "KOREAN" && studentMenu == null) {
                            studentMenu = parsed.menu
                            studentKcal = parsed.kcal
                        }
                        "FACULTY" -> if (groupJson.optString("menuType") == "KOREAN" && facultyMenu == null) {
                            facultyMenu = parsed.menu
                            facultyKcal = parsed.kcal
                        }
                    }
                }
            }
        }

        return WidgetMealData(
            mealOfDay = mealOfDay,
            dormKoreanMenu = dormKoreanMenu ?: emptyList(),
            dormKoreanKcal = dormKoreanKcal,
            dormHalalMenu  = dormHalalMenu  ?: emptyList(),
            dormHalalKcal  = dormHalalKcal,
            studentMenu    = studentMenu    ?: emptyList(),
            studentKcal    = studentKcal,
            facultyMenu    = facultyMenu    ?: emptyList(),
            facultyKcal    = facultyKcal,
        )
    }

    private data class ParsedMenuGroup(val menu: List<String>, val kcal: Int?)

    private fun parseRegularMenuGroup(groupJson: JSONObject, languageCode: String): ParsedMenuGroup? {
        val sections = groupJson.getJSONArray("sections")
        val menu = mutableListOf<String>()
        val calories = mutableListOf<Int>()

        for (i in 0 until sections.length()) {
            val sectionJson = sections.getJSONObject(i)
            if (sectionJson.optString("sectionType") != "REGULAR") continue

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
            kcal = if (calories.size == 1) calories.first() else null
        )
    }

    private fun localizedMenuName(itemJson: JSONObject, languageCode: String): String {
        val ko = itemJson.getString("ko")
        if (!languageCode.startsWith("en")) return ko

        val en = itemJson.optString("en", "")
        return en.takeIf { it.isNotBlank() } ?: ko
    }

    private fun currentLanguageCode(context: Context?): String {
        if (context == null) return Locale.getDefault().language

        val config = context.resources.configuration
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val locales = config.locales
            if (locales.size() > 0) locales.get(0).language else Locale.getDefault().language
        } else {
            @Suppress("DEPRECATION")
            config.locale?.language ?: Locale.getDefault().language
        }
    }

    private fun writeCache(context: Context?, json: String) {
        if (context == null) return
        try {
            val file = File(context.filesDir, MEAL_CACHE_FILE)
            val tmp = File(context.filesDir, "$MEAL_CACHE_FILE.tmp.${System.nanoTime()}")
            tmp.writeText(json, Charsets.UTF_8)
            if (!tmp.renameTo(file)) {
                if (file.exists()) file.delete()
                if (!tmp.renameTo(file)) tmp.delete()
            }
        } catch (e: Exception) {
            // Network data was already parsed for this widget update; cache write-back is best effort.
        }
    }

    private fun httpGet(urlStr: String): String {
        val conn = URL(urlStr).openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 8000
        conn.readTimeout = 8000
        return try {
            conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }
}

fun menuFromData(data: WidgetMealData, cafeteria: Int): List<String> = when (cafeteria) {
    CAFE_DORM_KOREAN -> data.dormKoreanMenu
    CAFE_DORM_HALAL  -> data.dormHalalMenu
    CAFE_STUDENT     -> data.studentMenu
    CAFE_FACULTY     -> data.facultyMenu
    else             -> data.studentMenu
}

fun kcalFromData(data: WidgetMealData, cafeteria: Int): Int? = when (cafeteria) {
    CAFE_DORM_KOREAN -> data.dormKoreanKcal
    CAFE_DORM_HALAL  -> data.dormHalalKcal
    CAFE_STUDENT     -> data.studentKcal
    CAFE_FACULTY     -> data.facultyKcal
    else             -> data.studentKcal
}
