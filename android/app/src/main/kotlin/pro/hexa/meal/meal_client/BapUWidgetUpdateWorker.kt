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

        fun updateAll(cls: Class<*>, fn: (Int) -> Unit) {
            for (id in manager.getAppWidgetIds(ComponentName(ctx, cls))) {
                try { fn(id) } catch (e: Exception) { Log.e(TAG, "update failed id=$id", e) }
            }
        }

        updateAll(BapUWidget2x2Provider::class.java)       { BapUWidget2x2Provider.updateWidget(ctx, manager, it, data) }
        updateAll(BapUWidget4x2DualProvider::class.java)   { BapUWidget4x2DualProvider.updateWidget(ctx, manager, it, data) }
        updateAll(BapUWidget4x2StatusProvider::class.java) { BapUWidget4x2StatusProvider.updateWidget(ctx, manager, it, data) }
        updateAll(BapUWidget4x4Provider::class.java)       { BapUWidget4x4Provider.updateWidget(ctx, manager, it, data) }

        return Result.success()
    }

    companion object {
        private const val TAG = "BapUWidgetUpdateWorker"
        private const val WORK_NAME = "bapu_widget_periodic_update"

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
