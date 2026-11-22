package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.Locale
import kotlin.math.roundToInt

class BapUWidgetMenuRenderingTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val items = listOf(
        "쌀밥", "매콤순두부국", "순살치킨까스&어니언S", "미트소스스파게티", "양상추샐러드", "배추김치",
    )

    @Test
    fun 같은_크기는_식당과_메뉴량과_줄바꿈이_달라도_같은_본문_크기를_사용한다() = onMain {
        val cafeterias = listOf(
            CAFE_STUDENT to (1..5).map { "반찬 $it" },
            CAFE_DORM_KOREAN to items,
            CAFE_FACULTY to (1..7).map { "Long menu with wrapping $it" },
            CAFE_DORM_HALAL to emptyList(),
        )
        val deviceConfig = instrumentation.targetContext.resources.configuration
        val metricCases = listOf(
            deviceConfig.densityDpi to deviceConfig.fontScale,
            213 to 1f,
            213 to 2f,
            640 to 1f,
            640 to 2f,
        ).distinct()
        for ((density, scale) in metricCases) for (width in listOf(147.25f, 313.5f)) {
            val context = context(density, scale)
            var expectedSize: Float? = null
            for ((cafeteria, content) in cafeterias) {
                val views = render(context, width, 200f, content, cafeteria)
                for (owner in applyOwners(context)) {
                    val root = views.apply(owner, null)
                    measure(root, context, width, 200f)
                    val ids = if (usesTwoColumnMenu(width)) listOf(R.id.tv_menu_left, R.id.tv_menu_right) else listOf(R.id.tv_menu)
                    val menus = ids.map { root.findViewById<TextView>(it) }
                    if (expectedSize == null) expectedSize = menus.first().textSize
                    menus.forEach { assertEquals(requireNotNull(expectedSize), it.textSize, 0.01f) }
                    assertTrue("고정한 본문 크기에서도 표시 영역을 넘어서는 안 된다", fits(menus))
                }
            }
        }
    }

    @Test
    fun 같은_폭에서_높이를_늘리면_본문_크기가_작아지지_않고_여유가_충분하면_커진다() = onMain {
        val cases = listOf(
            Triple(230.25f, 13f, listOf(150f, 190f, 210f, 230f, 260f, 320f)),
            Triple(313.5f, 14f, listOf(130f, 160f, 185f, 210f, 260f, 350f)),
        )
        for (density in listOf(213, 640)) {
            val context = context(density)
            for ((width, maxSp, heights) in cases) {
                var previousSize = 0f
                val selectedSizes = mutableListOf<Float>()
                for (height in heights) {
                    val views = render(context, width, height, items)
                    val root = views.apply(context, null)
                    measure(root, context, width, height)
                    val menuId = if (usesTwoColumnMenu(width)) R.id.tv_menu_left else R.id.tv_menu
                    val size = root.findViewById<TextView>(menuId).textSize
                    assertTrue("높이를 늘려도 본문 크기가 작아지면 안 된다: $width/$height", size + 0.01f >= previousSize)
                    assertTrue(size in px(context, 12f) - 0.01f..px(context, maxSp) + 0.01f)
                    previousSize = size
                    selectedSizes += size
                }
                assertEquals(px(context, 12f), selectedSizes.first(), 0.01f)
                assertTrue(
                    "여유가 충분한 크기에서는 최소 크기보다 커져야 한다: $width/$selectedSizes",
                    selectedSizes.last() > px(context, 12f) + 0.01f,
                )
                assertEquals(px(context, maxSp), selectedSizes.last(), 0.01f)
            }
        }
    }

    @Test
    fun 두열은_전체_메뉴와_순서를_보존하고_같은_본문_크기를_사용한다() = onMain {
        val deviceConfig = instrumentation.targetContext.resources.configuration
        val metricCases = listOf(
            deviceConfig.densityDpi to deviceConfig.fontScale,
            640 to 1f,
            640 to 2f,
        ).distinct()
        for ((density, scale) in metricCases) {
            val context = context(density, scale)
            val views = render(context, 313.5f, 350f, items)
            for (owner in applyOwners(context)) {
                val root = views.apply(owner, null)
                measure(root, context, 313.5f, 350f)
                val menus = listOf(R.id.tv_menu_left, R.id.tv_menu_right).map { root.findViewById<TextView>(it) }
                assertEquals(View.VISIBLE, root.findViewById<View>(R.id.menu_columns).visibility)
                assertEquals(items.joinToString("\n"), menus.joinToString("\n") { it.text.toString() })
                if (scale == 1f) {
                    assertEquals(px(context, 14f), menus[0].textSize, 0.01f)
                } else {
                    assertTrue(menus[0].textSize in px(context, 12f) - 0.01f..px(context, 14f) + 0.01f)
                }
                assertEquals(menus[0].textSize, menus[1].textSize, 0.01f)
                assertTrue("두 열 모두 배정된 높이에 들어가야 한다", fits(menus))
                for ((id, sp) in listOf(R.id.tv_cafeteria_name to 13f, R.id.tv_meal_of_day to 13f, R.id.tv_status to 11f)) {
                    assertEquals(px(context, sp), root.findViewById<TextView>(id).textSize, 0.01f)
                }
                assertTrue(root.findViewById<TextView>(R.id.tv_cafeteria_name).typeface.isBold)
                assertFalse(root.findViewById<TextView>(R.id.tv_meal_of_day).typeface.isBold)
                // XML의 android:lineSpacingExtra는 getDimensionPixelSize로 정수 픽셀 반올림된다.
                menus.forEach { assertEquals(px(context, 4f).roundToInt().toFloat(), it.lineSpacingExtra, 0.01f) }
            }
        }
    }

    @Test
    fun 고정한_본문_크기에서_넘치면_부분_말줄임하고_높이와_표시_줄_수를_지킨다() = onMain {
        val deviceConfig = instrumentation.targetContext.resources.configuration
        val metricCases = listOf(
            deviceConfig.densityDpi to deviceConfig.fontScale,
            640 to 1f,
        ).distinct()
        val cases = listOf(
            120f to listOf("쌀밥", "🍚🍜".repeat(30)),
            2000f to (1..21).map { "메뉴 $it" },
        )
        for ((density, scale) in metricCases) {
            val context = context(density, scale)
            for ((height, content) in cases) {
                val views = render(context, 147f, height, content)
                for (owner in applyOwners(context)) {
                    val root = views.apply(owner, null)
                    measure(root, context, 147f, height)
                    val menu = root.findViewById<TextView>(R.id.tv_menu)
                    assertTrue(menu.textSize in px(context, 12f) - 0.01f..px(context, 13f) + 0.01f)
                    val text = menu.text.toString()
                    assertTrue(text.endsWith("…"))
                    val prefix = text.removeSuffix("…")
                    assertTrue(content.joinToString("\n").startsWith(prefix))
                    assertFalse("이모지 중간을 잘라서는 안 된다", prefix.lastOrNull()?.isHighSurrogate() == true)
                    assertTrue("말줄임한 텍스트는 실제 표시 영역과 20줄 상한을 지켜야 한다", fits(listOf(menu)))
                }
            }
        }
    }

    @Test
    fun 영어_2칸_폭에서는_식당명만_표시하고_3칸_이상이나_한국어에서는_식사시간을_함께_표시한다() = onMain {
        val enContext = context(640, locale = Locale.ENGLISH)
        for ((width, cafeteria) in listOf(147.25f to CAFE_DORM_KOREAN, 147.25f to CAFE_STUDENT, 180f to CAFE_DORM_KOREAN)) {
            val root = render(enContext, width, 160f, items, cafeteria, mealOfDay = 0, languageCode = "en")
                .apply(enContext, null)
            assertEquals(View.VISIBLE, root.findViewById<TextView>(R.id.tv_cafeteria_name).visibility)
            assertEquals(View.GONE, root.findViewById<TextView>(R.id.tv_meal_of_day).visibility)
        }

        val wideEn = render(enContext, 230.25f, 200f, items, CAFE_DORM_KOREAN, mealOfDay = 0, languageCode = "en")
            .apply(enContext, null)
        assertEquals(View.VISIBLE, wideEn.findViewById<TextView>(R.id.tv_meal_of_day).visibility)

        val koContext = context(640, locale = Locale.KOREAN)
        val koRoot = render(koContext, 147.25f, 160f, items, CAFE_DORM_KOREAN, mealOfDay = 1)
            .apply(koContext, null)
        assertEquals(View.VISIBLE, koRoot.findViewById<TextView>(R.id.tv_meal_of_day).visibility)
    }

    @Test
    fun 정적_미리보기_레이아웃은_영어에서_식사시간을_숨기고_한국어에서는_표시한다() = onMain {
        for (nightMode in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
            val koContext = themedContext(context(640, locale = Locale.KOREAN), nightMode)
            val koRoot = RemoteViews(koContext.packageName, R.layout.widget_2x2_preview).apply(koContext, null)
            assertEquals(View.VISIBLE, koRoot.findViewById<TextView>(R.id.tv_meal_of_day).visibility)

            val enContext = themedContext(context(640, locale = Locale.ENGLISH), nightMode)
            val enRoot = RemoteViews(enContext.packageName, R.layout.widget_2x2_preview).apply(enContext, null)
            assertEquals(View.GONE, enRoot.findViewById<TextView>(R.id.tv_meal_of_day).visibility)
        }
    }

    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.VANILLA_ICE_CREAM)
    fun 생성형_미리보기는_실제_렌더_규칙과_테마_색을_유지한다() = onMain {
        val koContext = context(640, locale = Locale.KOREAN)
        val koPreview = BapUWidget2x2Provider.createPreviewRemoteViews(koContext, "ko")
        for (nightMode in listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES)) {
            val themed = themedContext(koContext, nightMode)
            val root = koPreview.apply(themed, null)
            measure(root, themed, WIDGET_PREVIEW_SIZE_DP, WIDGET_PREVIEW_SIZE_DP)
            assertEquals(View.VISIBLE, root.findViewById<TextView>(R.id.tv_meal_of_day).visibility)
            assertEquals(themed.getColor(R.color.widget_status_open), root.findViewById<TextView>(R.id.tv_status).currentTextColor)
            assertTrue(fits(listOf(root.findViewById(R.id.tv_menu))))
        }

        val enContext = context(640, locale = Locale.ENGLISH)
        val enPreview = BapUWidget2x2Provider.createPreviewRemoteViews(enContext, "en")
        val enRoot = enPreview.apply(enContext, null)
        measure(enRoot, enContext, WIDGET_PREVIEW_SIZE_DP, WIDGET_PREVIEW_SIZE_DP)
        assertEquals(enContext.getString(R.string.cafeteria_dormitory), enRoot.findViewById<TextView>(R.id.tv_cafeteria_name).text.toString())
        assertEquals(enContext.getString(R.string.food_korean), enRoot.findViewById<TextView>(R.id.tv_food_type).text.toString())
        assertEquals(View.GONE, enRoot.findViewById<TextView>(R.id.tv_meal_of_day).visibility)
        assertTrue(fits(listOf(enRoot.findViewById(R.id.tv_menu))))
    }

    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.VANILLA_ICE_CREAM)
    fun API35_이상에서는_생성형_미리보기를_등록하고_조회할_수_있다() {
        val targetContext = instrumentation.targetContext
        val languageCode = BapUWidgetMealRepository.currentLanguageCode(targetContext)
        val localized = BapUWidgetMealRepository.localizedContext(targetContext, languageCode)
        val preview = BapUWidget2x2Provider.createPreviewRemoteViews(targetContext, languageCode)
        val manager = AppWidgetManager.getInstance(targetContext)
        val provider = ComponentName(targetContext, BapUWidget2x2Provider::class.java)

        val applied = manager.setWidgetPreview(
            provider,
            AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN,
            preview,
        )
        assumeTrue("시스템 호출 빈도 제한으로 생성형 미리보기 등록 검증을 건너뜀", applied)

        // Android 16+(remoteViewsProto)에서는 시스템이 미리보기를 비동기로 저장한 뒤
        // generatedPreviewCategories를 갱신하므로 짧은 유예 시간 동안 반영을 기다린다.
        val deadline = SystemClock.elapsedRealtime() + 2_000L
        while (!BapUWidget2x2Provider.hasGeneratedHomeScreenPreview(manager, targetContext.packageName, provider) &&
            SystemClock.elapsedRealtime() < deadline
        ) {
            Thread.sleep(25L)
        }
        assertTrue(
            "등록 후 시스템이 홈 화면 생성형 미리보기 보유를 보고해야 한다",
            BapUWidget2x2Provider.hasGeneratedHomeScreenPreview(manager, targetContext.packageName, provider),
        )
        val saved = manager.getWidgetPreview(
            provider,
            null,
            AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN,
        )
        assertNotNull("등록에 성공한 홈 화면 생성형 미리보기를 조회할 수 있어야 한다", saved)

        onMain {
            val root = requireNotNull(saved).apply(localized, null)
            measure(root, localized, WIDGET_PREVIEW_SIZE_DP, WIDGET_PREVIEW_SIZE_DP)
            assertEquals(
                localized.getString(R.string.cafeteria_dormitory),
                root.findViewById<TextView>(R.id.tv_cafeteria_name).text.toString(),
            )
            assertEquals(
                localized.getString(R.string.food_korean),
                root.findViewById<TextView>(R.id.tv_food_type).text.toString(),
            )
            assertEquals(
                if (showsWidgetMealOfDay(languageCode, WIDGET_PREVIEW_SIZE_DP)) View.VISIBLE else View.GONE,
                root.findViewById<TextView>(R.id.tv_meal_of_day).visibility,
            )
            assertTrue(fits(listOf(root.findViewById(R.id.tv_menu))))
        }
    }

    /**
     * AOSP에서는 다른 패키지 Context로 RemoteViews.apply() 시 내부 createApplicationContext()가
     * 기기 기본 densityDpi/fontScale로 되돌린다. 따라서 임의 밀도·배율은 targetContext로,
     * 기기 실제 밀도·배율과 일치하는 케이스는 다른 패키지(런처 경로)까지 함께 검증한다.
     */
    private fun applyOwners(context: Context): List<Context> {
        val deviceConfig = instrumentation.targetContext.resources.configuration
        val targetConfig = context.resources.configuration
        val matchesDeviceMetrics = targetConfig.densityDpi == deviceConfig.densityDpi &&
            targetConfig.fontScale == deviceConfig.fontScale
        return if (matchesDeviceMetrics) {
            listOf(context, instrumentation.context.createConfigurationContext(targetConfig))
        } else {
            listOf(context)
        }
    }

    private fun themedContext(base: Context, nightMode: Int): Context =
        base.createConfigurationContext(Configuration(base.resources.configuration).apply {
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or nightMode
        })

    private fun context(density: Int, scale: Float = 1f, locale: Locale = Locale.KOREAN): Context {
        val configuration = Configuration(instrumentation.targetContext.resources.configuration).apply {
            densityDpi = density
            fontScale = scale
            setLocale(locale)
        }
        return instrumentation.targetContext.createConfigurationContext(configuration)
    }

    @Test
    fun 크기_목록이_없는_런처도_가로와_세로의_실제_높이에_맞게_표시한다() = onMain {
        val base = context(640)
        val options = Bundle().apply {
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 230)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 314)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
            putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 350)
        }
        val companion = BapUWidget2x2Provider.Companion
        val method = companion.javaClass.getDeclaredMethod(
            "createFallbackRemoteViews", Context::class.java, Int::class.javaPrimitiveType,
            WidgetMealData::class.java, Bundle::class.java,
        ).apply { isAccessible = true }
        val views = method.invoke(companion, base, AppWidgetManager.INVALID_APPWIDGET_ID, data(items), options) as RemoteViews
        for (orientation in listOf(Configuration.ORIENTATION_PORTRAIT, Configuration.ORIENTATION_LANDSCAPE)) {
            val landscape = orientation == Configuration.ORIENTATION_LANDSCAPE
            val owner = base.createConfigurationContext(Configuration(base.resources.configuration).apply {
                this.orientation = orientation
            })
            val root = views.apply(owner, null)
            measure(root, owner, if (landscape) 314f else 230f, if (landscape) 110f else 350f)
            val ids = if (landscape) listOf(R.id.tv_menu_left, R.id.tv_menu_right) else listOf(R.id.tv_menu)
            val menus = ids.map { root.findViewById<TextView>(it) }
            assertTrue("선택된 방향의 높이에 들어가야 한다", fits(menus))
            if (landscape) {
                assertEquals(View.VISIBLE, root.findViewById<View>(R.id.menu_columns).visibility)
                assertTrue("가로에서 넘치는 메뉴는 생략을 표시해야 한다", menus.any { it.text.endsWith("…") })
            } else {
                assertEquals(items.joinToString("\n"), menus.single().text.toString())
            }
        }
    }

    private fun data(content: List<String>, mealOfDay: Int = 2, languageCode: String = "ko") = WidgetMealData(
        mealOfDay = mealOfDay, dormKoreanMenu = content, dormHalalMenu = content,
        studentMenu = content, facultyMenu = content, languageCode = languageCode,
        operatingResults = mapOf(
            CAFE_DORM_KOREAN to OperatingResult(OperatingStatus.CLOSED),
            CAFE_DORM_HALAL to OperatingResult(OperatingStatus.OPEN),
            CAFE_STUDENT to OperatingResult(OperatingStatus.BEFORE_OPEN, nextStartH = 11, nextStartM = 30),
            CAFE_FACULTY to OperatingResult(OperatingStatus.NO_SERVICE),
        ),
    )

    private fun render(
        context: Context,
        width: Float,
        height: Float,
        content: List<String>,
        cafeteria: Int = CAFE_DORM_KOREAN,
        mealOfDay: Int = 2,
        languageCode: String = "ko",
    ): RemoteViews {
        // 실사용 RemoteViews 생성 경로를 검증하되 테스트를 위해 앱의 공개 API를 늘리지 않는다.
        val companion = BapUWidget2x2Provider.Companion
        val render = companion.javaClass.getDeclaredMethod(
            "createRemoteViews", Context::class.java, Int::class.javaPrimitiveType,
            WidgetMealData::class.java, Float::class.javaPrimitiveType, Float::class.javaPrimitiveType,
        ).apply { isAccessible = true }
        return render.invoke(
            companion, context, cafeteria, data(content, mealOfDay, languageCode), width, height,
        ) as RemoteViews
    }

    private fun measure(root: View, context: Context, width: Float, height: Float) {
        val widthPx = dpToPx(context, width).toInt()
        val heightPx = dpToPx(context, height).toInt()
        root.measure(exact(widthPx), exact(heightPx))
        root.layout(0, 0, widthPx, heightPx)
    }

    private fun fits(menus: List<TextView>): Boolean = menus.all { menu ->
        val assignedHeight = menu.measuredHeight
        val width = menu.measuredWidth
        menu.maxLines = Int.MAX_VALUE
        menu.measure(exact(width), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        menu.lineCount <= 20 && menu.measuredHeight <= assignedHeight + 1
    }

    private fun px(context: Context, sp: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, context.resources.displayMetrics)

    private fun exact(size: Int) = View.MeasureSpec.makeMeasureSpec(size, View.MeasureSpec.EXACTLY)

    private fun onMain(block: () -> Unit) {
        var failure: Throwable? = null
        instrumentation.runOnMainSync {
            try { block() } catch (error: Throwable) { failure = error }
        }
        failure?.let { throw it }
    }
}
