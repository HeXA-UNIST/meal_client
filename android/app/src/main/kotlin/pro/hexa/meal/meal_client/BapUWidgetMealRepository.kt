package pro.hexa.meal.meal_client

import android.content.Context
import android.content.res.Configuration
import java.io.File
import java.util.Calendar
import java.util.Locale
import org.json.JSONObject

object BapUWidgetMealRepository {
    fun fetch(context: Context, languageCode: String): WidgetMealData {
        val hours = BapUWidgetOperatingHours.loadRequiredFromCache(context)
        val calendar = Calendar.getInstance(BapUWidgetTime.kstTimeZone)
        val mealOfDay = BapUWidgetOperatingHours.currentMealOfDay(hours, calendar)
        val dayType = BapUWidgetTime.dayOfWeekApiKey(calendar)
        val data = selectMealData(
            canonicalFile = File(context.filesDir, BapUWidgetContract.MEAL_CACHE_FILE),
            nextWeekFile = File(context.filesDir, BapUWidgetContract.NEXT_MEAL_CACHE_FILE),
            targetWeekStart = BapUWidgetTime.kstWeekStartApiValue(calendar),
            dayType = dayType,
            mealOfDay = mealOfDay,
            languageCode = languageCode,
        ) ?: WidgetMealData.empty(mealOfDay)
        // 한 render pass가 같은 시각과 같은 info.json 해석을 공유하도록 여기서 한 번만 계산한다.
        // responsive RemoteViews의 size별 렌더가 다시 파일을 읽지 않게 한다.
        val operatingResults = CAFE_OPTIONS.associateWith { cafeteria ->
            requireNotNull(BapUWidgetOperatingHours.statusFor(hours, cafeteria, mealOfDay.index, calendar))
        }
        return data.copy(operatingResults = operatingResults)
    }

    /// payload week.startDate가 현재 KST 주와 일치하는 파일을 고른다.
    /// canonical meal.json은 월요일 이후 동일 주 데이터가 둘일 때 우선한다.
    internal fun selectMealData(
        canonicalFile: File,
        nextWeekFile: File,
        targetWeekStart: String,
        dayType: String,
        mealOfDay: WidgetMealOfDay,
        languageCode: String = "ko",
    ): WidgetMealData? = listOf(canonicalFile, nextWeekFile).firstNotNullOfOrNull { file ->
        if (!file.isFile) return@firstNotNullOfOrNull null
        runCatching {
            val json = file.readText(Charsets.UTF_8)
            val root = JSONObject(json)
            if (root.optJSONObject("week")?.optString("startDate") != targetWeekStart) {
                return@runCatching null
            }
            BapUWidgetMealParser.parse(
                json = json,
                dayType = dayType,
                mealType = mealOfDay.apiKey,
                mealOfDay = mealOfDay,
                languageCode = languageCode,
            )
        }.getOrNull()
    }

    internal fun currentLanguageCode(context: Context): String {
        // Flutter의 SharedPreferences API와 같은 저장소·접두사를 사용한다.
        val saved = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.settings_locale", null)
        return requireSavedLanguageCode(saved)
    }

    internal fun requireSavedLanguageCode(code: String?): String {
        check(code == "ko" || code == "en") { "Saved app locale is missing or invalid" }
        return requireNotNull(code)
    }

    // 앱 언어에 맞춘 리소스 컨텍스트로 위젯 제목과 상태도 번역한다.
    internal fun localizedContext(context: Context, languageCode: String): Context {
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(Locale.forLanguageTag(requireSavedLanguageCode(languageCode)))
        return context.createConfigurationContext(configuration)
    }
}
