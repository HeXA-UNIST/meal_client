package pro.hexa.meal.meal_client

import android.content.Context
import android.os.Build
import java.io.File
import java.util.Calendar
import java.util.Locale

object BapUWidgetMealRepository {
    fun fetch(context: Context): WidgetMealData {
        val hours = BapUWidgetOperatingHours.loadRequiredFromCache(context)
        val calendar = Calendar.getInstance(BapUWidgetTime.kstTimeZone)
        val mealOfDay = BapUWidgetOperatingHours.currentMealOfDay(hours, calendar)
        val dayType = BapUWidgetTime.dayOfWeekApiKey(calendar)
        val languageCode = currentLanguageCode(context)
        val file = File(context.filesDir, BapUWidgetContract.MEAL_CACHE_FILE)

        if (!file.isFile || !hasFreshMealCache(file.lastModified())) {
            return WidgetMealData.empty(mealOfDay)
        }

        return runCatching {
            BapUWidgetMealParser.parse(
                json = file.readText(Charsets.UTF_8),
                dayType = dayType,
                mealType = mealOfDay.apiKey,
                mealOfDay = mealOfDay,
                languageCode = languageCode
            )
        }.getOrElse {
            WidgetMealData.empty(mealOfDay)
        }
    }

    internal fun hasFreshMealCache(lastModifiedMs: Long, nowMs: Long = System.currentTimeMillis()): Boolean =
        BapUWidgetTime.kstWeekId(lastModifiedMs) == BapUWidgetTime.kstWeekId(nowMs)

    private fun currentLanguageCode(context: Context): String {
        val config = context.resources.configuration
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val locales = config.locales
            if (locales.size() > 0) locales.get(0).language else Locale.getDefault().language
        } else {
            @Suppress("DEPRECATION")
            config.locale?.language ?: Locale.getDefault().language
        }
    }
}
