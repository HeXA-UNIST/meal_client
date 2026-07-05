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
 * "운영 시작"이나 "마감 임박 N분 전" 같은 상태 전환 시각에 맞춰 정확한 시각 호출
 * (안드로이드 AlarmManager)을 예약해 전환 순간에 바로 위젯을 갱신한다.
 *
 * 마감 임박 구간(종료 45분 전 ~ 종료)에는 "N분 남음" 카운트다운이 계속 바뀌므로, 그 구간
 * 안에서는 1분마다 호출되도록 예약한다. 그 외 시간에는 다음 경계(운영 시작 또는 마감임박
 * 시작)까지 한 번에 건너뛴다.
 */
object BapUWidgetScheduleManager {
    private const val TAG = "BapUWidgetScheduleManager"
    private const val REQUEST_CODE = 5100
    private const val ACTION_SCHEDULED_UPDATE = "pro.hexa.meal.meal_client.action.WIDGET_SCHEDULED_UPDATE"
    private val KST = TimeZone.getTimeZone("Asia/Seoul")

    /** 다음 경계(또는 마감임박 중이면 다음 1분) 시점에 갱신 호출을 예약한다. 기존 예약은 자동으로 대체된다. */
    fun scheduleNext(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val now = Calendar.getInstance(KST)
        val scheduleData = try {
            val hours = BapUWidgetOperatingHours.loadRequiredFromCache(context)
            val periods = BapUWidgetOperatingHours.periodsForToday(hours, now)
            val transitions = BapUWidgetOperatingHours.mealTransitionsForToday(hours, now)
            Pair(periods, transitions)
        } catch (e: WidgetInfoCacheException) {
            Log.e(TAG, "cannot schedule widget update without valid info cache", e)
            cancel(context)
            return
        }
        val (periods, transitions) = scheduleData
        val triggerAtMillis = now.timeInMillis + millisUntilNextWake(now, periods, transitions)
        val pi = pendingIntent(context)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        } else {
            // 정확한 시각 호출 권한이 없는 기기: 다소 늦게 올 수 있지만 Doze 상태에서도 결국은 온다.
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        }
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

        if (isWithinAnyClosingSoonWindow(nowMins, periods)) {
            return 60_000L - elapsedInCurrentMinuteMs
        }

        val boundaries = allBoundaryMinutesToday(periods, transitions)
        val nextToday = boundaries.filter { it > nowMins }.minOrNull()
        val targetMins = nextToday ?: (boundaries.min() + 24 * 60)
        return (targetMins - nowMins) * 60_000L - elapsedInCurrentMinuteMs
    }

    /** 현재 분(자정 기준)이 어떤 식당이든 "마감 N분 전(45분)" 구간 안에 있는지. */
    private fun isWithinAnyClosingSoonWindow(nowMins: Int, periods: List<OperatingPeriod>): Boolean =
        periods.any { p ->
            val endMins = p.endH * 60 + p.endM
            nowMins in (endMins - 45) until endMins
        }

    /** 오늘의 "운영 시작" 시각 + "마감 45분 전" 시각을 자정 기준 분 단위로 모은 것(중복 제거). */
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
            result.add(p.endH * 60 + p.endM - 45)
        }
        return result.toList()
    }
}
