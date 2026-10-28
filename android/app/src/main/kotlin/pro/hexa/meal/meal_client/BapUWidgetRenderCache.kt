package pro.hexa.meal.meal_client

internal data class WidgetRenderInputs(
    val data: WidgetMealData,
    val cafeteria: Int,
    val sizes: List<Pair<Float, Float>>,
    val configuration: String,
    val exactAlarmAllowed: Boolean,
)

/** 프로세스가 바뀌면 다시 그리며, 렌더 성공 후에만 생략 기준을 기억한다. */
internal class BapUWidgetRenderCache {
    private val rendered = mutableMapOf<Int, WidgetRenderInputs>()

    fun update(widgetId: Int, inputs: WidgetRenderInputs, skipUnchanged: Boolean, render: () -> Unit) {
        if (skipUnchanged && rendered[widgetId] == inputs) return
        // 실패한 강제 갱신도 다음 요청에서 재시도할 수 있게 이전 기록을 지운다.
        rendered.remove(widgetId)
        render()
        rendered[widgetId] = inputs
    }

    fun remove(widgetId: Int) {
        rendered.remove(widgetId)
    }
}
