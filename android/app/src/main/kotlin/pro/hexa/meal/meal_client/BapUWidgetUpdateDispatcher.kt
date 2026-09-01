package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.annotation.Keep
import java.util.concurrent.Executors
import java.util.function.Consumer

/**
 * 위젯 렌더의 공통 진입점이다. 데이터 갱신은 Dart cache writer가 맡고, native는 cache-only로
 * 다시 그린다. 순수 native 주기 안전망이 필요해지면 provider XML의 updatePeriodMillis
 * (최소 30분, coarse하지만 권한/코드 부담이 작음)를 후속 검토 후보로 쓸 수 있다.
 */
@Keep
object BapUWidgetUpdateDispatcher {
    private const val TAG = "BapUWidgetUpdateDispatcher"

    /**
     * provider, receiver, 설정 화면, Flutter bridge에서 들어오는 렌더를 한 줄로 실행한다.
     * 캐시 쓰기는 이 큐의 책임이 아니며, 요청 합치기나 우선순위도 두지 않는다. 순서대로
     * 끝까지 실행하는 것만으로 오래된 렌더가 뒤늦게 새 화면을 덮는 일을 막는다.
     */
    private val renderExecutor = Executors.newSingleThreadExecutor { command ->
        Thread(command, "BapUWidgetRender")
    }

    fun execute(block: () -> Unit) {
        renderExecutor.execute {
            try {
                block()
            } catch (error: Exception) {
                // 각 진입점이 결과를 직접 전달한 뒤에도 남을 수 있는 예외가 Android process의
                // uncaught exception이 되지 않도록 executor 경계에서 마지막으로 차단한다.
                Log.e(TAG, "uncaught widget task failure", error)
            }
        }
    }

    /** Flutter plugin은 app 모듈을 직접 의존할 수 없어 reflection으로 이 메서드를 호출한다. */
    @Keep
    @JvmStatic
    fun enqueueRenderAllWidgets(context: Context, completion: Consumer<Throwable?>) {
        val appContext = context.applicationContext
        execute {
            val failure = runCatching { renderAllWidgets(appContext) }.exceptionOrNull()
            completion.accept(failure)
        }
    }

    fun renderAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val data = BapUWidgetFetcher.fetch(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, BapUWidget2x2Provider::class.java))
        val failures = updateBestEffort(ids) { id ->
            BapUWidget2x2Provider.updateWidget(context, manager, id, data)
        }
        if (failures.isNotEmpty()) {
            throw WidgetRenderException(failures)
        }
    }

    /** Broadcast 경로는 다른 ID를 계속 갱신하고 실패를 logcat에 남기는 것으로 끝낸다. */
    fun renderAllWidgetsLenient(context: Context) {
        try {
            renderAllWidgets(context)
        } catch (e: Exception) {
            Log.e(TAG, e.message, e)
        }
    }

    fun renderWidgetIds(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
        update: (Int, WidgetMealData) -> Unit
    ) {
        val data = BapUWidgetFetcher.fetch(context)
        updateBestEffort(widgetIds) { id -> update(id, data) }
            .forEach { failure ->
                Log.e(TAG, "update failed id=${failure.widgetId}", failure.cause)
            }
    }

    internal fun updateBestEffort(
        widgetIds: IntArray,
        update: (Int) -> Unit,
    ): List<WidgetRenderFailure> = buildList {
        for (id in widgetIds) {
            try {
                update(id)
            } catch (error: Exception) {
                add(WidgetRenderFailure(id, error))
            }
        }
    }

    fun hasAnyWidget(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return manager.getAppWidgetIds(ComponentName(context, BapUWidget2x2Provider::class.java)).isNotEmpty()
    }

}

internal data class WidgetRenderFailure(val widgetId: Int, val cause: Exception)

internal class WidgetRenderException(failures: List<WidgetRenderFailure>) :
    IllegalStateException(
        "${failures.size} widget render(s) failed: ${failures.joinToString { it.widgetId.toString() }}",
        failures.first().cause,
    ) {
    init {
        failures.drop(1).forEach { addSuppressed(it.cause) }
    }
}
