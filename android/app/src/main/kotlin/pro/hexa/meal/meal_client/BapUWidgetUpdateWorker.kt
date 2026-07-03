package pro.hexa.meal.meal_client

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

class BapUWidgetUpdateWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {

    override fun doWork(): Result {
        val ctx = applicationContext
        val manager = AppWidgetManager.getInstance(ctx)
        val data = BapUWidgetFetcher.fetch(ctx)

        // 캐시도 없고 네트워크도 실패한 경우 재시도 요청
        if (data == null) return Result.retry()

        updateAllWidgets(ctx, manager, data)
        // 운영시간 경계 호출 예약이 어떤 이유로든 끊겼을 경우를 대비한 재동기화(안전장치).
        BapUWidgetScheduleManager.scheduleNext(ctx)

        return Result.success()
    }

    companion object {
        private const val TAG = "BapUWidgetUpdateWorker"
        private const val WORK_NAME = "bapu_widget_periodic_update"

        /** 4개 위젯 종류 전부에 대해 현재 등록된 인스턴스를 갱신한다. */
        fun updateAllWidgets(context: Context, manager: AppWidgetManager, data: WidgetMealData?) {
            fun updateAll(cls: Class<*>, fn: (Int) -> Unit) {
                for (id in manager.getAppWidgetIds(ComponentName(context, cls))) {
                    try { fn(id) } catch (e: Exception) { Log.e(TAG, "update failed id=$id", e) }
                }
            }

            updateAll(BapUWidget2x2Provider::class.java)       { BapUWidget2x2Provider.updateWidget(context, manager, it, data) }
            updateAll(BapUWidget4x2DualProvider::class.java)   { BapUWidget4x2DualProvider.updateWidget(context, manager, it, data) }
            updateAll(BapUWidget4x2StatusProvider::class.java) { BapUWidget4x2StatusProvider.updateWidget(context, manager, it, data) }
            updateAll(BapUWidget4x4Provider::class.java)       { BapUWidget4x4Provider.updateWidget(context, manager, it, data) }
        }

        fun schedule(context: Context) {
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(
                    WORK_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    PeriodicWorkRequestBuilder<BapUWidgetUpdateWorker>(15, TimeUnit.MINUTES).build()
                )
        }

        fun enqueueOneTime(context: Context) {
            WorkManager.getInstance(context).enqueue(
                OneTimeWorkRequestBuilder<BapUWidgetUpdateWorker>().build()
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }

        fun hasAnyWidget(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return listOf(
                BapUWidget2x2Provider::class.java,
                BapUWidget4x2DualProvider::class.java,
                BapUWidget4x2StatusProvider::class.java,
                BapUWidget4x4Provider::class.java
            ).any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
        }
    }
}
