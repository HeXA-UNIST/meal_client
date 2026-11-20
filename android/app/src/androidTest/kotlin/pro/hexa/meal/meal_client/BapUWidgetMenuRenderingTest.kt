package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class BapUWidgetMenuRenderingTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val sizes = listOf(12f, 12.5f, 13f, 13.5f, 14f)
    private val items = listOf(
        "쌀밥", "매콤순두부국", "순살치킨까스&어니언S", "미트소스스파게티", "양상추샐러드", "배추김치",
    )

    @Test
    fun 한열은_소수_픽셀_환경에서도_전체_메뉴가_들어가는_최대_크기를_선택한다() = onMain {
        for (density in listOf(213, 640)) for (height in listOf(190f, 200f, 203f)) {
            val context = context(density)
            val views = render(context, 230.25f, height, items)
            for (owner in listOf(context, instrumentation.context.createConfigurationContext(context.resources.configuration))) {
                val root = views.apply(owner, null)
                val menu = root.findViewById<TextView>(R.id.tv_menu)
                measure(root, context, 230.25f, height)
                val fullText = items.joinToString("\n")
                val displayedText = menu.text.toString()
                val selected = sizes.single { kotlin.math.abs(px(context, it) - menu.textSize) < 0.01f }
                assertTrue("선택한 텍스트가 실제 표시 영역에 들어가야 한다", fits(listOf(menu)))
                if (displayedText != fullText) {
                    assertEquals(12f, selected, 0f)
                    assertTrue(displayedText.endsWith("…"))
                    menu.text = fullText
                    measure(root, context, 230.25f, height)
                    assertFalse("전체 메뉴가 최소 크기로 들어갈 때는 생략하면 안 된다", fits(listOf(menu)))
                    continue
                }
                // 더 큰 후보는 실제 TextView에 전체 메뉴를 넣었을 때 공간을 넘어야 한다.
                for (larger in sizes.filter { it > selected }) {
                    menu.setTextSize(TypedValue.COMPLEX_UNIT_SP, larger)
                    measure(root, context, 230.25f, height)
                    assertFalse("들어가는 더 큰 후보를 건너뛰면 안 된다: $density/$height/$larger", fits(listOf(menu)))
                }
            }
        }
    }

    @Test
    fun 두열은_전체_메뉴와_순서를_보존하고_같은_본문_크기를_사용한다() = onMain {
        for (scale in listOf(1f, 2f)) {
            val context = context(640, scale)
            val views = render(context, 313.5f, 350f, items)
            for (owner in listOf(context, instrumentation.context.createConfigurationContext(context.resources.configuration))) {
                val root = views.apply(owner, null)
                measure(root, context, 313.5f, 350f)
                val menus = listOf(R.id.tv_menu_left, R.id.tv_menu_right).map { root.findViewById<TextView>(it) }
                assertEquals(View.VISIBLE, root.findViewById<View>(R.id.menu_columns).visibility)
                assertEquals(items.joinToString("\n"), menus.joinToString("\n") { it.text.toString() })
                assertEquals(px(context, 14f), menus[0].textSize, 0.01f)
                assertEquals(menus[0].textSize, menus[1].textSize, 0.01f)
                assertTrue("두 열 모두 배정된 높이에 들어가야 한다", fits(menus))
                for ((id, sp) in listOf(R.id.tv_cafeteria_name to 13f, R.id.tv_meal_of_day to 12f, R.id.tv_status to 11f)) {
                    assertEquals(px(context, sp), root.findViewById<TextView>(id).textSize, 0.01f)
                }
                menus.forEach { assertEquals(px(context, 4f), it.lineSpacingExtra, 0.01f) }
            }
        }
    }

    @Test
    fun 최소_크기에서도_넘치면_부분_말줄임하고_높이와_표시_줄_수를_지킨다() = onMain {
        val context = context(640)
        val cases = listOf(
            120f to listOf("쌀밥", "🍚🍜".repeat(30)),
            2000f to (1..21).map { "메뉴 $it" },
        )
        for ((height, content) in cases) {
            val views = render(context, 147f, height, content)
            val root = views.apply(instrumentation.context.createConfigurationContext(context.resources.configuration), null)
            measure(root, context, 147f, height)
            val menu = root.findViewById<TextView>(R.id.tv_menu)
            assertEquals(px(context, 12f), menu.textSize, 0.01f)
            val text = menu.text.toString()
            assertTrue(text.endsWith("…"))
            val prefix = text.removeSuffix("…")
            assertTrue(content.joinToString("\n").startsWith(prefix))
            assertFalse("이모지 중간을 잘라서는 안 된다", prefix.lastOrNull()?.isHighSurrogate() == true)
            assertTrue("말줄임한 텍스트는 실제 표시 영역과 20줄 상한을 지켜야 한다", fits(listOf(menu)))
        }
    }

    private fun context(density: Int, scale: Float = 1f): Context {
        val configuration = Configuration(instrumentation.targetContext.resources.configuration).apply {
            densityDpi = density
            fontScale = scale
            setLocale(Locale.KOREAN)
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

    private fun data(content: List<String>) = WidgetMealData(
        mealOfDay = 2, dormKoreanMenu = content, languageCode = "ko",
        operatingResults = mapOf(CAFE_DORM_KOREAN to OperatingResult(OperatingStatus.CLOSED)),
    )

    private fun render(context: Context, width: Float, height: Float, content: List<String>): RemoteViews {
        // 실사용 RemoteViews 생성 경로를 검증하되 테스트를 위해 앱의 공개 API를 늘리지 않는다.
        val companion = BapUWidget2x2Provider.Companion
        val render = companion.javaClass.getDeclaredMethod(
            "createRemoteViews", Context::class.java, Int::class.javaPrimitiveType,
            WidgetMealData::class.java, Float::class.javaPrimitiveType, Float::class.javaPrimitiveType,
        ).apply { isAccessible = true }
        return render.invoke(companion, context, AppWidgetManager.INVALID_APPWIDGET_ID, data(content), width, height) as RemoteViews
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
