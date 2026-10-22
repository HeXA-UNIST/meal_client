package pro.hexa.meal.meal_client

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar
import java.util.TimeZone

/**
 * 자정, 끼니 전환, 운영 시작, 마감 임박 시작, 운영 종료 중 다음 경계에 위젯 갱신을 예약한다.
 * 정확한 알람 권한이 있으면 setExact로 예약하고, 없으면 기존 inexact 방식을 유지한다.
 * setExact도 Doze 중에는 지연될 수 있다. 캐시 오류 재확인에는 정확한 알람을 쓰지 않는다.
 */
object BapUWidgetScheduleManager {
    private const val TAG = "BapUWidgetScheduleManager"
    private const val REQUEST_CODE = 5100
    private const val CACHE_RETRY_DELAY_MILLIS = 30 * 60_000L
    private const val ACTION_SCHEDULED_UPDATE = "pro.hexa.meal.meal_client.action.WIDGET_SCHEDULED_UPDATE"
    private val KST = TimeZone.getTimeZone("Asia/Seoul")

    fun canScheduleExactAlarms(context: Context): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
    }

    /** 다음 표시 경계에 갱신 호출을 예약한다. 같은 PendingIntent의 기존 예약을 대체한다. */
    fun scheduleNext(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val now = Calendar.getInstance(KST)
        var retryingCache = false
        val delayMillis = try {
            val hours = BapUWidgetOperatingHours.loadRequiredFromCache(context)
            val periods = BapUWidgetOperatingHours.periodsForToday(hours, now)
            val transitions = BapUWidgetOperatingHours.mealTransitionsForToday(hours, now)
            millisUntilNextWake(now, periods, transitions)
        } catch (e: WidgetInfoCacheException) {
            // 캐시 복구는 Flutter가 맡는다. 읽기에 실패해도 재확인 기회를 남겨
            // 캐시가 복구된 뒤 운영시간 경계 예약으로 돌아갈 수 있게 한다.
            Log.e(TAG, "invalid info cache; retry widget update in 30 minutes", e)
            retryingCache = true
            CACHE_RETRY_DELAY_MILLIS
        }
        val triggerAtMillis = now.timeInMillis + delayMillis
        val pi = pendingIntent(context)

        if (!retryingCache && canScheduleExactAlarms(context)) {
            try {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
                Log.d(TAG, "scheduled exact widget update at=$triggerAtMillis")
                return
            } catch (e: SecurityException) {
                // 권한을 사용할 수 없게 된 경우에도 위젯 갱신 예약은 남긴다.
                Log.w(TAG, "exact alarm unavailable; using inexact widget update", e)
            }
        }
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        Log.d(TAG, "scheduled inexact widget update at=$triggerAtMillis cacheRetry=$retryingCache")
    }

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        am.cancel(pendingIntent(context))
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, BapUWidgetScheduledUpdateReceiver::class.java).setAction(ACTION_SCHEDULED_UPDATE)
        return PendingIntent.getBroadcast(
            context, REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** 지금부터 다음 호출까지 남은 시간(ms). */
    internal fun millisUntilNextWake(
        now: Calendar,
        periods: List<OperatingPeriod>,
        transitions: WidgetMealTransitionMinutes,
    ): Long {
        val nowMins = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val nowSec = now.get(Calendar.SECOND)
        val nowMs = now.get(Calendar.MILLISECOND)
        val elapsedInCurrentMinuteMs = nowSec * 1000L + nowMs

        val boundaries = allBoundaryMinutesToday(periods, transitions)
        val nextToday = boundaries.filter { it > nowMins }.minOrNull()
        val targetMins = nextToday ?: (boundaries.min() + 24 * 60)
        return (targetMins - nowMins) * 60_000L - elapsedInCurrentMinuteMs
    }

    /** 오늘 상태가 바뀌는 시각을 자정 기준 분 단위로 모은다(중복 제거). */
    internal fun allBoundaryMinutesToday(
        periods: List<OperatingPeriod>,
        transitions: WidgetMealTransitionMinutes,
    ): List<Int> {
        val result = sortedSetOf(
            0,
            transitions.breakfastEndMinutes + 1,
            transitions.lunchEndMinutes + 1,
        )
        for (p in periods) {
            result.add(p.startH * 60 + p.startM)
            result.add(p.endH * 60 + p.endM - BapUWidgetContract.MealTime.CLOSING_SOON_THRESHOLD_MINUTES)
            result.add(p.endH * 60 + p.endM)
        }
        return result.toList()
    }
}
