package pro.hexa.meal.meal_client

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkManager
import androidx.work.WorkerParameters

/**
 * Legacy WorkManager entrypoint kept so previously scheduled work does not resolve to a missing
 * class after upgrade. Active widget refresh paths call BapUWidgetUpdateDispatcher directly.
 */
class BapUWidgetUpdateWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {

    override fun doWork(): Result {
        cancelLegacy(applicationContext)
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "bapu_widget_periodic_update"

        fun cancelLegacy(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
