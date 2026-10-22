package pro.hexa.meal.meal_client

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker

/** 저장된 Flutter dispatcher로 캐시 기반 알림 복구만 실행한다. 네트워크는 필요 없다. */
internal object BapUNotificationPermissionRecovery {
    const val TASK_NAME = "bapu_notification_permission_recovery"

    fun enqueue(context: Context) {
        val request = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
            .setInputData(Data.Builder().putString(BackgroundWorker.DART_TASK_KEY, TASK_NAME).build())
            .build()
        // 중복 허용 이벤트는 합치고, 실제 설정·예약의 동시 변경은 Dart의 파일 잠금으로 보호한다.
        WorkManager.getInstance(context).enqueueUniqueWork(TASK_NAME, ExistingWorkPolicy.KEEP, request)
    }
}
