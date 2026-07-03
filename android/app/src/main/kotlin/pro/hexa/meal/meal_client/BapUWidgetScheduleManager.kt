package pro.hexa.meal.meal_client

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar
import java.util.TimeZone

/**
 * 15분 주기 워커만으로는 "운영 시작"이나 "마감 임박 N분 전" 같은 상태 전환이 최대 15분
 * 늦게 반영된다. 운영 시간 경계는 [operatingPeriod]에 이미 고정값으로 정의돼 있으므로,
 * 그 시각에 맞춰 정확한 시각 호출(안드로이드 AlarmManager)을 예약해 전환 순간에 바로
 * 위젯을 갱신한다.
 *
 * 마감 임박 구간(종료 45분 전 ~ 종료)에는 "N분 남음" 카운트다운이 계속 바뀌므로, 그 구간
 * 안에서는 1분마다 호출되도록 예약한다. 그 외 시간에는 다음 경계(운영 시작 또는 마감임박
 * 시작)까지 한 번에 건너뛴다.
 */
object BapUWidgetScheduleManager {
    private const val REQUEST_CODE = 5100
    private const val ACTION_SCHEDULED_UPDATE = "pro.hexa.meal.meal_client.action.WIDGET_SCHEDULED_UPDATE"
    private val KST = TimeZone.getTimeZone("Asia/Seoul")

    /** 다음 경계(또는 마감임박 중이면 다음 1분) 시점에 갱신 호출을 예약한다. 기존 예약은 자동으로 대체된다. */
    fun scheduleNext(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val now = Calendar.getInstance(KST)
        val triggerAtMillis = now.timeInMillis + millisUntilNextWake(now)
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
    private fun millisUntilNextWake(now: Calendar): Long {
        val nowMins = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val nowSec = now.get(Calendar.SECOND)
        val nowMs = now.get(Calendar.MILLISECOND)
        val elapsedInCurrentMinuteMs = nowSec * 1000L + nowMs

        if (isWithinAnyClosingSoonWindow(nowMins)) {
            return 60_000L - elapsedInCurrentMinuteMs
        }

        val boundaries = allBoundaryMinutesToday()
        val nextToday = boundaries.filter { it > nowMins }.minOrNull()
        val targetMins = nextToday ?: (boundaries.min() + 24 * 60)
        return (targetMins - nowMins) * 60_000L - elapsedInCurrentMinuteMs
    }

    /** 현재 분(자정 기준)이 어떤 식당이든 "마감 N분 전(45분)" 구간 안에 있는지. */
    private fun isWithinAnyClosingSoonWindow(nowMins: Int): Boolean =
        allPeriodsToday().any { p ->
            val endMins = p.endH * 60 + p.endM
            nowMins in (endMins - 45) until endMins
        }

    /** 오늘의 "운영 시작" 시각 + "마감 45분 전" 시각을 자정 기준 분 단위로 모은 것(중복 제거). */
    private fun allBoundaryMinutesToday(): List<Int> {
        val result = sortedSetOf<Int>()
        for (p in allPeriodsToday()) {
            result.add(p.startH * 60 + p.startM)
            result.add(p.endH * 60 + p.endM - 45)
        }
        return result.toList()
    }

    private fun allPeriodsToday(): List<OperatingPeriod> {
        val cafeterias = listOf(CAFE_DORM_KOREAN, CAFE_STUDENT, CAFE_FACULTY)
        return cafeterias.flatMap { cafeteria -> (0..2).mapNotNull { operatingPeriod(cafeteria, it) } }
    }
}
