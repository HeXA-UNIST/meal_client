package pro.hexa.meal.meal_client

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.SharedPreferenceHelper
import dev.fluttercommunity.workmanager.buildTaskInputData
import java.util.concurrent.TimeUnit

/** 앱이 닫혀 있을 때 위젯 추가·삭제에도 Flutter의 주기 갱신을 맞춘다. */
internal object BapUMealBackgroundRefresh {
    // Dart meal_background_refresh_io.dart의 이름·간격·네트워크 제약과 같아야 한다.
    private const val TASK_NAME = "bapu_meal_refresh"

    fun sync(context: Context) {
        enqueue(context, null)
    }

    /** UPDATE로 실행 중인 작업을 보존하고 다음 실행만 조정한다. */
    fun postpone(context: Context, notBeforeMillis: Long) {
        enqueue(context, notBeforeMillis)
    }

    private fun enqueue(context: Context, notBeforeMillis: Long?) {
        val notificationsEnabled = context
            .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.settings_notification_enabled", false)
        val manager = WorkManager.getInstance(context)
        if (!notificationsEnabled && !BapUWidgetUpdateDispatcher.hasAnyWidget(context)) {
            manager.cancelUniqueWork(TASK_NAME)
            return
        }
        // 앱을 아직 실행하지 않았다면 Dart 진입점이 없으므로 최초 실행에 맡긴다.
        if (SharedPreferenceHelper.getCallbackHandle(context) == -1L) return
        val request = PeriodicWorkRequest.Builder(BackgroundWorker::class.java, 2, TimeUnit.HOURS)
            .setInputData(buildTaskInputData(TASK_NAME, null, uniqueName = TASK_NAME))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .apply {
                if (notBeforeMillis != null) setNextScheduleTimeOverride(notBeforeMillis)
            }
            .build()
        val policy = if (notBeforeMillis == null) ExistingPeriodicWorkPolicy.KEEP else ExistingPeriodicWorkPolicy.UPDATE
        val operation = manager.enqueueUniquePeriodicWork(TASK_NAME, policy, request)
        // MethodChannel은 DB 반영까지 확인하고, 실패하면 기존 작업을 그대로 둔다.
        if (notBeforeMillis != null) operation.result.get()
    }
}
