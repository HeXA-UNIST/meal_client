package pro.hexa.meal.meal_client

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.util.Calendar

data class WidgetOperatingHours(
    val weekday: Map<WidgetCafeteria, Map<WidgetMealOfDay, OperatingPeriod>>,
    val weekend: Map<WidgetCafeteria, Map<WidgetMealOfDay, OperatingPeriod>>,
)

class WidgetInfoCacheException(message: String) : IllegalStateException(message)

object BapUWidgetOperatingHours {
    fun loadFromCache(context: Context): WidgetOperatingHours? {
        val file = File(context.filesDir, BapUWidgetContract.INFO_CACHE_FILE)
        if (!file.isFile) return null
        return parseRawInfo(runCatching { file.readText() }.getOrNull() ?: return null)
    }

    fun loadRequiredFromCache(context: Context): WidgetOperatingHours {
        val file = File(context.filesDir, BapUWidgetContract.INFO_CACHE_FILE)
        if (!file.isFile) throw WidgetInfoCacheException("missing ${BapUWidgetContract.INFO_CACHE_FILE}")
        val rawInfo = runCatching { file.readText() }
            .getOrElse { throw WidgetInfoCacheException("unreadable ${BapUWidgetContract.INFO_CACHE_FILE}") }
        return parseRawInfo(rawInfo)
            ?: throw WidgetInfoCacheException("invalid ${BapUWidgetContract.INFO_CACHE_FILE}")
    }

    fun parseRawInfo(rawInfo: String): WidgetOperatingHours? = runCatching {
        if (rawInfo.isBlank()) return null
        val operatingHours = JSONObject(rawInfo).optJSONObject("operatingHours") ?: return null
        WidgetOperatingHours(
            weekday = parsePeriod(operatingHours.optJSONObject("weekday") ?: return null),
            weekend = parsePeriod(operatingHours.optJSONObject("weekend") ?: return null),
        )
    }.getOrNull()

    fun statusFor(
        hours: WidgetOperatingHours?,
        cafeteria: Int,
        mealOfDay: Int,
        now: Calendar = Calendar.getInstance(BapUWidgetTime.kstTimeZone),
    ): OperatingResult? {
        val period = periodFor(hours, cafeteria, mealOfDay, now) ?: return null
        val nowMins = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val startMins = period.startH * 60 + period.startM
        val endMins = period.endH * 60 + period.endM

        return when {
            nowMins < startMins -> OperatingResult(OperatingStatus.BEFORE_OPEN)
            nowMins < endMins -> {
                val left = endMins - nowMins
                if (left >= BapUWidgetContract.MealTime.CLOSING_SOON_THRESHOLD_MINUTES) {
                    OperatingResult(OperatingStatus.OPEN)
                } else {
                    OperatingResult(OperatingStatus.CLOSING_SOON, left)
                }
            }
            nowMins <= endMins + BapUWidgetContract.MealTime.JUST_CLOSED_DURATION_MINUTES ->
                OperatingResult(OperatingStatus.JUST_CLOSED)
            else -> OperatingResult(OperatingStatus.BEFORE_OPEN)
        }
    }

    fun statusFor(
        context: Context,
        cafeteria: Int,
        mealOfDay: Int,
        now: Calendar = Calendar.getInstance(BapUWidgetTime.kstTimeZone),
    ): OperatingResult? = statusFor(loadFromCache(context), cafeteria, mealOfDay, now)

    fun periodsForToday(
        hours: WidgetOperatingHours?,
        now: Calendar = Calendar.getInstance(BapUWidgetTime.kstTimeZone),
    ): List<OperatingPeriod> {
        val map = periodMapForDate(hours, now) ?: return emptyList()
        return map.values
            .flatMap { it.values }
            .distinct()
            .sortedWith(compareBy<OperatingPeriod> { it.startH }.thenBy { it.startM }.thenBy { it.endH }.thenBy { it.endM })
    }

    fun periodsForToday(context: Context): List<OperatingPeriod> =
        periodsForToday(loadFromCache(context), Calendar.getInstance(BapUWidgetTime.kstTimeZone))

    fun mealTransitionsForToday(
        hours: WidgetOperatingHours,
        now: Calendar = Calendar.getInstance(BapUWidgetTime.kstTimeZone),
    ): WidgetMealTransitionMinutes {
        val map = periodMapForDate(hours, now)
            ?: throw WidgetInfoCacheException("missing operatingHours for date")
        val breakfastEnd = latestEndMinutes(map, WidgetMealOfDay.BREAKFAST)
            ?: throw WidgetInfoCacheException("missing breakfast operatingHours")
        val lunchEnd = latestEndMinutes(map, WidgetMealOfDay.LUNCH)
            ?: throw WidgetInfoCacheException("missing lunch operatingHours")
        if (breakfastEnd >= lunchEnd) {
            throw WidgetInfoCacheException("invalid meal transition order")
        }
        return WidgetMealTransitionMinutes(
            breakfastEndMinutes = breakfastEnd,
            lunchEndMinutes = lunchEnd,
        )
    }

    fun currentMealOfDay(
        hours: WidgetOperatingHours,
        now: Calendar = Calendar.getInstance(BapUWidgetTime.kstTimeZone),
    ): WidgetMealOfDay {
        val nowMins = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return BapUWidgetTime.mealOfDayForMinutes(nowMins, mealTransitionsForToday(hours, now))
    }

    private fun periodFor(
        hours: WidgetOperatingHours?,
        cafeteria: Int,
        mealOfDay: Int,
        now: Calendar,
    ): OperatingPeriod? {
        val cafe = when (WidgetCafeteria.fromPrefValue(cafeteria)) {
            WidgetCafeteria.DORM_HALAL -> WidgetCafeteria.DORM_KOREAN
            else -> WidgetCafeteria.fromPrefValue(cafeteria)
        }
        val meal = WidgetMealOfDay.fromIndex(mealOfDay)
        return periodMapForDate(hours, now)?.get(cafe)?.get(meal)
    }

    private fun periodMapForDate(
        hours: WidgetOperatingHours?,
        now: Calendar,
    ): Map<WidgetCafeteria, Map<WidgetMealOfDay, OperatingPeriod>>? {
        if (hours == null) return null
        return if (isWeekend(now)) hours.weekend else hours.weekday
    }

    private fun latestEndMinutes(
        map: Map<WidgetCafeteria, Map<WidgetMealOfDay, OperatingPeriod>>,
        meal: WidgetMealOfDay,
    ): Int? = map.values
        .mapNotNull { it[meal] }
        .maxOfOrNull { it.endH * 60 + it.endM }

    private fun isWeekend(now: Calendar): Boolean =
        now.get(Calendar.DAY_OF_WEEK) == Calendar.SATURDAY ||
            now.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY

    private fun parsePeriod(json: JSONObject): Map<WidgetCafeteria, Map<WidgetMealOfDay, OperatingPeriod>> =
        buildMap {
            parseCafeteria(json, "dormitory")?.let { put(WidgetCafeteria.DORM_KOREAN, it) }
            parseCafeteria(json, "student")?.let { put(WidgetCafeteria.STUDENT, it) }
            parseCafeteria(json, "faculty")?.let { put(WidgetCafeteria.FACULTY, it) }
        }

    private fun parseCafeteria(json: JSONObject, key: String): Map<WidgetMealOfDay, OperatingPeriod>? {
        val cafeteriaJson = json.optJSONObject(key) ?: return null
        return buildMap {
            parseMeal(cafeteriaJson, "breakfast")?.let { put(WidgetMealOfDay.BREAKFAST, it) }
            parseMeal(cafeteriaJson, "lunch")?.let { put(WidgetMealOfDay.LUNCH, it) }
            parseMeal(cafeteriaJson, "dinner")?.let { put(WidgetMealOfDay.DINNER, it) }
        }
    }

    private fun parseMeal(json: JSONObject, key: String): OperatingPeriod? {
        val mealJson = json.optJSONObject(key) ?: return null
        val start = parseHourMinute(mealJson.optString("start")) ?: return null
        val end = parseHourMinute(mealJson.optString("end")) ?: return null
        return OperatingPeriod(start.first, start.second, end.first, end.second)
    }

    private fun parseHourMinute(value: String): Pair<Int, Int>? {
        val parts = value.split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        return Pair(hour, minute)
    }
}
