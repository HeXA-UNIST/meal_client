package pro.hexa.meal.meal_client

import android.content.Context
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.GregorianCalendar
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
    private const val API_URL = "https://meal.hexa.pro/mainpage/data"
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
        loadFromFreshCache(context, dayType, mealType, mealOfDay)
            ?: fetchFromNetwork(context, dayType, mealType, mealOfDay)
    } catch (e: Exception) {
        null
    }

    private fun loadFromFreshCache(
        context: Context?,
        dayType: String,
        mealType: String,
        mealOfDay: Int
    ): WidgetMealData? {
        if (context == null) return null
        return try {
            val file = File(context.filesDir, MEAL_CACHE_FILE)
            if (!file.isFile || !hasFreshMealCache(file.lastModified())) return null
            parse(file.readText(Charsets.UTF_8), dayType, mealType, mealOfDay)
        } catch (e: Exception) {
            null
        }
    }

    private fun fetchFromNetwork(
        context: Context?,
        dayType: String,
        mealType: String,
        mealOfDay: Int
    ): WidgetMealData {
        val json = httpGet(API_URL)
        val data = parse(json, dayType, mealType, mealOfDay)
        writeCache(context, json)
        return data
    }

    private fun hasFreshMealCache(lastModifiedMs: Long): Boolean =
        kstWeekId(lastModifiedMs) == kstWeekId(System.currentTimeMillis())

    private fun kstWeekId(ms: Long): Long =
        (ms + KST_OFFSET_MS - WEEK_EPOCH_MS) / WEEK_MS

    private fun parse(json: String, dayType: String, mealType: String, mealOfDay: Int): WidgetMealData {
        val arr = JSONArray(json)
        if (arr.length() == 0) throw IllegalArgumentException("Empty meal API response")
        var dormKoreanMenu: List<String>? = null; var dormKoreanKcal: Int? = null
        var dormHalalMenu: List<String>? = null;  var dormHalalKcal: Int? = null
        var studentMenu: List<String>? = null;    var studentKcal: Int? = null
        var facultyMenu: List<String>? = null;    var facultyKcal: Int? = null

        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            if (obj.optString("dayType") != dayType) continue
            if (obj.optString("mealType") != mealType) continue

            val menus = obj.getJSONArray("menus").let { ja ->
                (0 until ja.length()).map { ja.getString(it) }
            }
            val kcal = obj.optInt("calorie", 0).takeIf { it > 0 }

            when (obj.optString("restaurantType")) {
                "기숙사 식당" -> when (obj.optString("dormitoryType")) {
                    "KOREAN" -> if (dormKoreanMenu == null) { dormKoreanMenu = menus; dormKoreanKcal = kcal }
                    "HALAL"  -> if (dormHalalMenu == null)  { dormHalalMenu  = menus; dormHalalKcal  = kcal }
                }
                "학생 식당"   -> if (studentMenu == null) { studentMenu = menus; studentKcal = kcal }
                "교직원 식당" -> if (facultyMenu == null) { facultyMenu = menus; facultyKcal = kcal }
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
