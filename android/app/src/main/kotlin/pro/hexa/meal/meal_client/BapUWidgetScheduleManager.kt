package pro.hexa.meal.meal_client

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar
import java.util.TimeZone

/**
 * 자정, 끼니 전환, 운영 시작, 마감 임박 시작, 운영 종료 중 다음 경계에 위젯 갱신을 예약한다.
 * 식단 위젯은 분 단위 정확성이 필요하지 않으므로 exact-alarm 특별 접근을 요구하지 않는다.
 * 시스템 절전 정책에 따라 실제 갱신은 경계보다 늦을 수 있다.
 */
object BapUWidgetScheduleManager {
    private const val TAG = "BapUWidgetScheduleManager"
    private const val REQUEST_CODE = 5100
    private const val ACTION_SCHEDULED_UPDATE = "pro.hexa.meal.meal_client.action.WIDGET_SCHEDULED_UPDATE"
    private val KST = TimeZone.getTimeZone("Asia/Seoul")

    /** 다음 표시 경계에 inexact 갱신 호출을 예약한다. 기존 예약은 자동으로 대체된다. */
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

        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
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
            result.add(p.endH * 60 + p.endM - 45)
            result.add(p.endH * 60 + p.endM)
        }
        return result.toList()
    }
}
