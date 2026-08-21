# iOS Meal Notification Migration — `zonedSchedule` Design

## Context

밥먹어U's meal notification feature lets a user pick up to 4 daily time
periods (morning/lunch/dinner/night), days of week, and target cafeterias.
With no keywords, the current product behavior sends one notification per
selected cafeteria/meal group containing the complete menu. Keywords are an
optional filter: they are currently visible and honored only in Debug builds
and are intended for a later release after the base notification delivery has
been validated. Release builds ignore any stored Debug keywords.

This is implemented via `Workmanager().registerOneOffTask(...)`
(`lib/features/notification/notification_scheduler.dart`): each fire
builds notification content against the live cache
(`meal_notification_worker.dart` → `_runMealKeywordCheck`) and re-registers
itself for the next occurrence. This works on Android (WorkManager persists
across reboot and auto-retries via `Result.retry()` on failure — confirmed in
`workmanager_android-0.10.7`'s `BackgroundWorker.kt:345`).

**Root cause (confirmed against the actually-resolved dependency source, not
docs)**: on iOS, `workmanager_apple` 0.9.10 (pinned in `pubspec.lock`)
implements `registerOneOffTask` using `UIApplication.beginBackgroundTask` +
`DispatchQueue.global().asyncAfter(...)` (`WorkmanagerPlugin.swift:91-124,
530-554`) — **not** `BGTaskScheduler`. This only fires if the app process
happens to stay alive for the full delay (often hours), which iOS does not
guarantee. iOS meal notifications are therefore structurally unreliable
today. This plan replaces the iOS delivery mechanism; Android's Workmanager
delivery path and fire-time content semantics remain unchanged.

**Considered and rejected — unifying Android onto `zonedSchedule` too.** Since
iOS moves to precomputed local notifications, one obvious option is to delete
the Android Workmanager self-rescheduling chain and run both platforms through
the same precomputed batch. Rejected: Android's fire-time evaluation is
strictly better and costs nothing to keep — it reads the live cache at
delivery, so it has no precomputed-content staleness, no empty-menu omission
risk, no pending-request cap, and no dependency on a reconciliation pass having
run beforehand. Unification would trade all of that away, and would
additionally require registering
`com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver`
(plugin `README.md:387-394`), which is **not** in
`android/app/src/main/AndroidManifest.xml` today even though
`SCHEDULE_EXACT_ALARM` and `RECEIVE_BOOT_COMPLETED` are already declared there
for widget alarms; WorkManager gives reboot survival for free. The only thing
unification would actually delete is the Android/iOS parity test — the shared
settings store and shared content builder specified below are worth doing
regardless, because they fix a worker-vs-`AppSettings` duplication that
predates this plan and exists on Android alone. Record this as a decision, not
a default, so it is not reopened during implementation.

**No migration compatibility is required**: the meal-notification feature
has not shipped. Delete the old iOS Workmanager scheduling path instead of
adding cleanup flags, callback suppression, or compatibility branches for
previously registered iOS tasks. The Android-specific Workmanager path remains
because Android intentionally keeps its current execution model.

**Confirmed product decision**: alert clock-time (e.g. "lunch 11:00") is
interpreted in **device local time** on iOS too, matching Android's existing
`nextEnabledFireTime` behavior. Target *date* / day-of-week / menu lookup
stay KST-anchored (unchanged, via `notificationTargetDateFor`/
`kstCalendarDate` in `meal_notification_period.dart`).

## Approach

Move iOS delivery off Workmanager one-off tasks onto
`flutter_local_notifications`' `zonedSchedule` — an OS-level
`UNUserNotificationCenter` request that persists and delivers without the
app process being alive. Since iOS can't reliably run Dart code at fire
time, **content (localized title/body) is precomputed** for a whole window of
upcoming (period, date, cafeteria/meal-group) tuples and rescheduled as a batch
whenever the source data, settings, or resolved app locale could have changed.

Use one-shot requests (`matchDateTimeComponents: null`), not repeating
`DayOfWeekAndTime`/daily triggers. Each date and cafeteria can have different
menu content, title, and body, so one repeating notification cannot represent
the precomputed content.

### Authorization (upstream of everything else in this plan)

`main.dart:52` calls `initNotifications()` unconditionally at cold start, and
`notification_service.dart:22-26` builds
`DarwinInitializationSettings(requestAlertPermission: true,
requestBadgePermission: true, requestSoundPermission: true)`. iOS therefore
shows the system authorization prompt on **first launch**, before the user has
seen the notification settings screen or expressed any interest in the feature.
iOS grants that prompt once per install. A user who declines it there loses
meal notifications permanently unless they later find the toggle in the
Settings app.

This is a design-level defect, not a UX detail, because of *how* it is expected
to fail: `UNUserNotificationCenter.add(_:withCompletionHandler:)` does not error
on an unauthorized app and `getPendingNotificationRequests` reflects the request
store rather than authorization, so `zonedSchedule` should still **succeed** and
`pendingNotificationRequests()` should still return the request. If so, the
deterministic ID ownership scheme, whole-slot packing, and the reconciliation
loop specified below would all report a perfectly healthy scheduled horizon
while nothing is ever presented to the user — indistinguishable, from the user's
side, from the Workmanager failure this plan exists to fix, and undetectable by
any amount of scheduling correctness.

This is the one load-bearing claim in this section that is **not** yet confirmed
against a runtime, only against Apple's API contract. Confirm it at the Phase 1
simulator gate (§ Verification) before relying on the framing: deny
authorization, schedule one request, and read back
`pendingNotificationRequests()`. The required changes below are worth making
either way — if the call turns out to fail loudly instead, the fix is the same
and merely becomes easier to observe.

Required changes:

- **Move the prompt to the opt-in moment.** Set `requestAlertPermission`,
  `requestBadgePermission`, and `requestSoundPermission` to `false` in
  `DarwinInitializationSettings`, making `initNotifications()` a pure,
  background-safe registration that is also correct to call from a headless
  isolate (trigger #5). Request authorization from the foreground UI only when
  the user enables meal notifications, via the existing
  `requestNotificationPermission()` (`notification_service.dart:44-58`), which
  already resolves the iOS implementation and asks for alert/badge/sound.
- **Make authorization an explicit precondition of reconciliation.** Read the
  status with
  `resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
  ?.checkPermissions()`
  (`platform_flutter_local_notifications.dart:780`, returns
  `NotificationsEnabledOptions`). When alerts are not enabled, **abort without
  mutating pending requests** and report the state instead of reporting
  success. This deliberately follows the same preserve-on-failure rule the
  reconciliation section applies to cache and network failures: unpresentable
  pending requests are inert, not harmful, and keeping them makes a re-grant
  take effect on the next resume instead of requiring a successful cache read
  first. Master disable and `resetAll()` remain the only unconditional
  cancellation paths, because those express user intent rather than a transient
  platform state.

  Plugin 22.3.0's `NotificationsEnabledOptions` cannot distinguish "never
  asked" from "denied", so model the usable result as three states:

  - *enabled* — proceed with reconciliation;
  - *not authorized* — the combined denied/not-determined state; abort without
    mutating and never prompt from reconciliation;
  - *not applicable* — a `null` result (non-iOS, or the implementation
    unavailable); proceed as if unrestricted, never treat as denied.

  Persistent UI copy for the combined state must be neutral rather than claim a
  definite denial, and must always provide a usable route to OS notification
  settings. A failed foreground opt-in request may use denial-specific transient
  feedback because that attempt's result is directly known.
- **Re-check on resume (Phase 2).** Authorization can be revoked or granted in the
  Settings app while the app is backgrounded. Resume reconciliation (trigger
  #3) already runs on every resume; fold the status read into it so a re-grant
  rebuilds the batch and a revocation updates the UI while leaving requests
  pending and inert.

Phase 1 includes the prompt move, reconciliation precondition, and opt-in denial
UI. The resume re-check belongs to Phase 2 together with the lifecycle trigger.
Authorization state is the first thing reconciliation checks, before any cache
read or batch construction.

### Delivery presentation (confirmed product decision)

Scheduling a request for 11:00 does not guarantee the user *sees* it at 11:00.
iOS Scheduled Summary and Focus modes hold notifications whose
`UNNotificationInterruptionLevel` is not time-sensitive and release them in the
user's next summary window, so a lunch alert can surface in the evening. Like
denied authorization, this is invisible to the scheduling layer: the request
fires on time and the OS defers presentation.

**Decision: use explicit `.active` presentation.** Meal menus are useful but do
not justify bypassing the user's Focus or Scheduled Summary policy. Scheduled
requests pass `InterruptionLevel.active` explicitly and remain eligible for
summary batching. The configured clock time is a trigger time, not a guarantee
that iOS presents the banner at that instant.
`DarwinNotificationDetails.interruptionLevel`
(`notification_details.dart:144`, `InterruptionLevel` enum in
`interruption_level.dart`) is the control. The rejected alternative was:

- **Request time-sensitive delivery.** `InterruptionLevel.timeSensitive`
  requires the `com.apple.developer.usernotifications.time-sensitive`
  capability/entitlement on the Runner target and corresponding provisioning.
  Unlike Critical Alerts, it is not described here as requiring a separate
  Apple pre-approval entitlement; it still must be used only for appropriately
  urgent content. A menu notification is a weak case for bypassing Focus.

Do not add the Time Sensitive capability or entitlement in this migration.

### Timezone mechanics (source-verified; simulator gate required)

Read `flutter_local_notifications-22.3.0`'s iOS channel end to end
(`FlutterLocalNotificationsPlugin.m:872-935`): for a one-shot `zonedSchedule`
call (no `matchDateTimeComponents`), the native side parses the Dart-sent
`scheduledDateTimeISO8601` string with `NSISO8601DateFormatter` — the
**offset embedded in the string** determines the absolute instant,
independent of the separately-sent `timeZoneName`. It then decomposes that
instant into Y/M/D/H/M/S/TimeZone components *in* `timeZoneName`'s zone and
builds a non-repeating `UNCalendarNotificationTrigger` with
`NSCalendarUnitTimeZone` included — so the absolute instant is preserved
regardless of which zone name is used for decomposition.

`tz.TZDateTime.from(candidateLocalDateTime, tz.UTC)` preserves the instant
represented by the device-local `DateTime` while serializing it with an
explicit UTC offset. `tz.UTC` is a zero-setup static constant in
`package:timezone` (confirmed present in the resolved `timezone: 0.11.1`), so
the Dart side does not need a timezone database for this approach. Build the
candidate the same way `nextEnabledFireTime` already does
(`DateTime(y, m, d, hour, minute)` in device local time), then wrap it with
`tz.TZDateTime.from(candidateLocal, tz.UTC)`.

One native-runtime assumption remains: the mapper sends `tz.UTC.name` as
`timeZoneName`, which is `Etc/UTC`, and iOS passes it to
`[NSTimeZone timeZoneWithName:]` before assigning it to the calendar. The
source path is confirmed, but acceptance of `Etc/UTC` on the supported Apple
runtimes is not yet established by this repository. Make a near-term
simulator delivery using this exact path the first Phase 1 gate. If lookup or
scheduling fails, stop this approach and add `flutter_timezone`, initialize
the timezone database, resolve the device's named location, and schedule with
that location instead. Verify the fallback package API at implementation time.

The resulting `UNCalendarNotificationTrigger` is pinned to that absolute
instant. If the user later changes the device timezone, already-pending
requests do not automatically move to the same wall-clock time in the new
zone. Resume reconciliation is therefore also the timezone-drift repair
mechanism: rebuild all meal-notification-owned pending requests using the
device's new local timezone. Until Phase 2 adds that trigger, Phase 1 has a
known gap for a timezone change made while the app remains installed but is
not relaunched.

Locale resolution must also match `MaterialApp`: use
`basicLocaleListResolution(PlatformDispatcher.instance.locales,
AppLocalizations.supportedLocales)`, not only the first device locale. Resolve
the locale once per immutable batch, use `AppLocalizations` for titles and
cafeteria/meal labels, and use `MealMenuItem.textFor(languageCode)` so English
menu text falls back to Korean exactly as it does on meal cards. Pending iOS
requests contain precomputed text, so resume reconciliation is also the repair
mechanism after a per-app/system language change.

Action: promote `timezone` from transitive to a direct entry in
`pubspec.yaml` (version already locked at `0.11.1`, no bump needed) since
we'll import it directly.

### Target-date ↔ fire-instant inversion (the real correctness risk)

All existing code goes fire-time → target-date. Precompute needs the
inverse. For a device far from KST, a local-clock candidate can resolve to
a KST date off by one day, so naive inversion is unsafe.

Add one pure function in `notification_scheduler.dart`, alongside
`nextEnabledFireTime` which it parallels:

```
DateTime fireInstantForTarget({
  required MealNotificationPeriod period,
  required DateTime targetKstDate,
  required TimeOfDay alertTime,
  LocalDateTimeFactory? localDateTimeFactory,
})
```

Compute the naive local candidate, then **verify** by running the existing,
already-tested `notificationTargetDateFor(period, candidate)` on it and only
accept the candidate if it round-trips to `targetKstDate` (retry ±1 local
day if not).

The factory defaults to Dart's device-local `DateTime(...)` constructor. Tests
inject a factory that converts wall-clock fields using a chosen UTC offset, so
UTC, UTC-8, UTC+9, and UTC+13 can be exercised in one test process. Without
this injection the proposed multi-offset property test would only test the
host machine's local timezone. The invariant is, for every period and target
date in the compute window:

```
notificationTargetDateFor(
  period,
  fireInstantForTarget(...),
) == targetKstDate
```

Include tests around calendar boundaries and DST transition dates. The current
notification slots do not fall in the usual DST transition window, but the
wall-clock-to-instant conversion still needs an explicit contract.

### Compute window and batch

For each enabled period, compute content for every date in the current cached
week plus the next week when available, where day-of-week is enabled and the
fire instant hasn't passed yet. Use validated cache snapshots or `WeekMeal`
values supplied by the refresh operation that triggered the reconciliation.
Reuse `mealsForNotificationTarget`, `mealContainsKeyword`, and the existing
`_buildMealNotificationContents` rules from `meal_notification_worker.dart` —
do not reimplement content logic.

First remove the current split settings interpretation. Today
`AppSettings._loadNotification` and the Android worker separately derive
cafeterias and dormitory meal types from preferences, including legacy
defaults, while only the worker applies the Release keyword gate. Their
results currently agree, but a future change could make Android fire-time
content and iOS precomputed content diverge before the shared content builder
ever sees its input.

Use two shared layers rather than mixing persistence migration into content
formatting:

- a notification-settings store/loader owns `SharedPreferences` keys, absent-
  key defaults, and legacy migration, and returns one `NotificationSettings`;
  both `AppSettings` and the Android worker use it;
- a pure delivery-settings normalizer owns the effective cafeterias,
  dormitory meal types, trimmed keywords, and the Debug/Release keyword gate.
  Production callers do not independently replace keywords with `[]`; tests
  may inject whether the unreleased keyword filter is enabled.

Then extract optional-keyword matching, localization, and title/body
formatting into a shared pure module,
`meal_notification_content_builder.dart`. Both the Android worker and the iOS
precompute path consume the same normalized delivery-settings snapshot and
call this module. Its contract is:

- empty keywords: one notification per selected non-empty meal group;
  localized full cafeteria name in the title, and every visible menu item in
  one body line separated by ` / `;
- non-empty keywords (Debug-only today): preserve the existing aggregated
  keyword-match content;
- English menu items use `textFor('en')`, including Korean fallback, and all
  labels/titles come from the one resolved `AppLocalizations` snapshot.

Add a pure iOS batch builder alongside the iOS scheduling orchestration:

```
List<({int id, DateTime fireInstant, String title, String body})>
buildMealNotificationBatch({
  required alertTimes, enabledDays, keywords, cafeterias, dormMealTypes,
  required AppLocalizations l10n,
  required DateTime now,
  required WeekMeal currentWeekMeal,
  WeekMeal? nextWeekMeal,
})
```

- **ID scheme**: reserve `[100_000_000, 140_000_000)` for scheduled meal
  requests and use
  `id = 100_000_000 + period.index * 10_000_000 + groupCode * 1_000_000 +
  daysSinceEpoch(targetDate)`. Stable group codes are `0` dormitory Korean,
  `1` dormitory Halal, `2` student, `3` faculty, and `9` aggregated keyword
  content. A generic dormitory `Meal` is not a group: notification settings
  expose only Korean and Halal, so other dormitory meal types are skipped.
  This is inside the plugin's signed 32-bit
  requirement, does not overlap the current immediate IDs `1`–`4`/`9`, and
  prevents different cafeterias at the same period/date from replacing one
  another. Recomputing the same tuple replaces only that request. The range
  alone identifies owned pending requests; do not add a payload marker or
  persisted ID ledger.
- **Cap**: iOS has a documented 64 pending-notification limit (package
  README). Use `kMaxScheduledMealNotifications = 64`; there is no second
  scheduled-notification producer that justifies reserving eight unused IDs.
  Empty-keyword mode can produce up to 4 notifications for one fire slot, so
  4 periods × 14 days is no longer the candidate maximum. Group
  candidates by `(fireInstant, period, targetDate)`, sort slots chronologically,
  and append a whole slot only when all of its cafeteria requests fit under
  the cap. Never cut a slot halfway and notify
  only some selected cafeterias. Stop before the first slot that does not fit.
  iOS's own eviction is documented — Apple DTS states the system keeps the
  soonest-firing 64 requests and discards the rest — so client-side
  nearest-first truncation is not distrust of the OS: it makes the retained set
  deterministic and unit-testable while moving in the same direction as the
  OS's eviction, so the two cannot disagree. The effective horizon therefore
  shrinks as the number of
  selected cafeterias/periods grows; launch/resume/refresh reconciliation
  replenishes it. The capacity is a real product constraint, not an
  implementation detail: with 4 periods and 4 meal groups, the 64-request cap
  holds exactly 4 fully populated target days. Because iOS does not
  guarantee BGAppRefresh, the app cannot simultaneously guarantee an
  arbitrarily long no-launch horizon, separate per-cafeteria notifications,
  and unrestricted selections. If seven-day offline delivery for the maximum
  selection is required, product scope must change (combine cafeterias, limit
  selections/periods, or use server-visible APNs).
  The implementation has no configuration-specific horizon branches: it always
  generates the available two-week candidates, sorts them chronologically, and
  greedily packs whole slots up to 64. The formulas and examples below only
  explain the resulting horizon. A daily BGAppRefresh request is an
  opportunistic top-up, never the sole condition for the next day's delivery.
- **Day filtering and packing**: `enabledDays` applies to the KST **menu target
  date**, matching the current worker/scheduler contract. Morning, lunch, and
  dinner normally fire on that date; the night period targets the next day's
  breakfast, so a Monday-enabled night notification fires Sunday night.
  Generate candidates only for enabled target dates before sorting/capping;
  disabled weekdays consume no pending-request capacity. Sort the remaining
  fire slots by absolute `fireInstant` and pack whole slots until the next slot
  would exceed 64. The ID contains `daysSinceEpoch(targetDate)`, not weekday,
  so Monday in different weeks cannot collide. A day-setting change cancels
  stale owned IDs before rebuilding.

  For stable non-empty menus, capacity is approximately
  `64 / (enabledPeriods × selectedMealGroups)` enabled target days. Examples:
  all 4 periods × all 4 groups gives 4 enabled days; 2 periods × 2 groups gives
  16 enabled days (therefore the full 14-day cache window); disabling Saturday
  and Sunday skips them and extends the calendar-time horizon without spending
  IDs. Packing uses actual non-empty group content, so a cafeteria with no menu
  for a slot consumes no request.
- **Minimum lead time**: build and retain only candidates at or after
  `now + kIosNotificationScheduleLeadTime` (initially 30 seconds), not merely
  `isAfter(now)`. The reactive `scheduledDate` `ArgumentError` handling below
  is the correctness backstop; this proactive margin merely keeps normal
  near-boundary skips and logs uncommon. Thirty seconds is an operational,
  non-derived initial value, not an iOS guarantee or correctness threshold.
  Re-read the clock immediately before each platform call and skip any
  candidate that has crossed the boundary.

Pass one complete immutable normalized delivery-settings and resolved-locale
snapshot to the builder. The shared normalizer, not each construction site,
forces empty effective keywords while the filter remains unreleased.

Do not combine `alertTimes`/`enabledDays` passed by `AppSettings` with a second,
hidden preferences read for keywords/cafeterias or a second locale resolution;
that can construct a batch from different settings or languages.

### Reconciliation and failure policy

Every reconciliation begins with the authorization check from § Authorization
above. If alerts are not enabled, report that state to the caller and stop
without reading caches, building a batch, or mutating any pending request —
the same preserve-on-failure treatment given to cache and network failures
below. An unauthorized run must never be reported as a successful
reconciliation.

The reconciler itself does not start network work. App launch/resume and meal
refresh orchestration decide whether a fetch is appropriate, then pass the
validated `WeekMeal` or let reconciliation read a validated cache snapshot.
This avoids duplicate fetches and a refresh → reconciliation → refresh cycle.
Treat a data-driven refresh differently from a user restriction:

- **Data refresh / launch / resume**: load and build before mutating pending
  requests. If current-week loading fails, preserve the existing meal
  requests. If next-week loading fails, reconcile only the current-week target
  range and leave previously scheduled next-week requests untouched. The next
  successful trigger replaces that possibly stale next-week portion.
- **User setting change**: honor the new setting immediately. Disabling the
  feature cancels all pending meal-notification requests without loading meal data.
  Removing/changing a keyword, period, day, cafeteria, or dorm meal type first
  cancels owned pending requests, then attempts to rebuild. Keyword mutations
  are Debug-only until that filter ships. If offline,
  missing notifications are preferable to sending content the user disabled.
- **All settings edits use one clear-first policy in this migration**, including
  expansions. This keeps the implementation small and makes the latest user
  settings authoritative, but an offline rebuild may temporarily reduce
  availability. Build-first optimization for expansions is deferred unless
  observed product behavior justifies the extra classification logic.

For a data-driven recompute:

0. Read the iOS authorization status. If alerts are not enabled, abort with
   that state and skip the remaining steps, leaving pending requests untouched.
1. Read the current-week `WeekMeal` from the validated cache, unless the caller
   already supplied the parsed result of a successful refresh. **If neither is
   available, abort the data-driven recompute and leave existing pending
   notifications untouched.** A foreground/background meal refresh will
   trigger reconciliation again after it succeeds.
2. Read the validated next-week cache snapshot, or use a supplied successful
   next-week refresh result. If neither is available, proceed with
   current-week-only reconciliation while retaining any existing next-week
   requests. Network fallback belongs to the launch/resume/refresh
   orchestration, not inside this reconciliation transaction.
3. Build the batch in memory (§ above).
4. Read pending requests and select only requests in the meal-notification
   feature's reserved ID range.
5. Cancel stale owned IDs in the target ranges successfully loaded for this
   recompute, then upsert every desired deterministic ID with `zonedSchedule`.
   Reusing an ID replaces that period/date/group request. Do not delete the
   next-week range when next-week loading failed.

`IOSFlutterLocalNotificationsPlugin.zonedSchedule` calls
`validateDateIsInTheFuture`, which throws `ArgumentError` in Release when a
one-shot date has become past. In the per-ID loop, catch `ArgumentError` only
for this race: require `error.name == 'scheduledDate'` and confirm that the
candidate is strictly before the newly read `clock.now()`, then log and skip
it. The plugin uses `isBefore`, so equality is accepted. If either condition
is false, rethrow because the error may indicate an invalid ID or another
programming defect. Other platform errors remain fatal to that reconciliation
attempt and observable to the caller.

Do not call application-wide `cancelAllPendingNotifications()`: it is safe only
while this feature happens to be the sole producer of scheduled notifications
and creates an unnecessary ownership dependency. Use
`pendingNotificationRequests()` plus per-ID `cancel()` for owned requests in
the reserved meal-notification range. Do not call `cancelAll()`,
which also removes delivered-but-undismissed
notifications from the tray.

`UNUserNotificationCenter` does not provide an atomic batch transaction.
"Build first" prevents data-load failure from wiping the old batch, but a
platform-channel failure halfway through reconciliation can still leave a
partial batch. Preserve this as an explicit residual risk, log/propagate the
failure, and retry on the next trigger. Test failure on the Nth schedule call;
do not describe this sequence as an atomic commit.

### Recompute trigger points

1. **App launch** — `main.dart`, near the existing
   `settings.rescheduleKeywordNotifications()` call, reconcile immediately
   from validated caches (rename that API to `rescheduleMealNotifications`
   when removing the obsolete keyword-only terminology). The normal foreground meal download then triggers a
   second reconciliation only if its validated payload differs.
2. **Settings change** — `lib/features/settings/app_settings.dart`. Only
   `setNotificationEnabled`, `setPeriodAlertTime`, `setNotificationDays`
   currently call `_requestNotificationReschedule` (confirmed by direct
   read). **`addNotificationKeyword`, `removeNotificationKeyword`,
   `setNotificationCafeterias`, `setNotificationDormMealTypes` do not** —
   harmless today (Android recomputes live at fire time) but becomes a real
   staleness bug once iOS content is precomputed: changing the selected
   cafeteria leaves missing/stale per-cafeteria requests, and a Debug keyword
   edit leaves stale text. **Fix: wire all four into the settings-change
   reconciliation path.** This path applies the immediate-cancel policy above
   for restrictions, rather than treating an offline rebuild as a reason to
   keep notifications based on removed settings.
   `setNotificationEnabled(true)` is additionally the **authorization opt-in
   moment**: request permission there (foreground only), and if it is denied,
   report that to the settings UI instead of proceeding to schedule a batch
   that iOS will never present.
3. **App resumed to foreground** — no app-level lifecycle observer exists
   today; `home_page.dart`'s `_HomePageState` has one but it's scoped to
   week-rollover meal-cache reload, not appropriate to piggyback on (mixes
   concerns, only fires on week change not every resume). Inject a small
   resume-listener registration function into `AppSettings`; its production
   implementation owns an `AppLifecycleListener` and returns a disposer. This
   is easier to fake than injecting the concrete framework listener. Register
   `onResume: () => rescheduleMealNotifications()` and dispose the returned
   subscription alongside `_notificationScheduleCoordinator` in the existing
   `dispose()` override. Resume first reconciles from cache, then requests one
   deduplicated foreground meal refresh under an explicit staleness policy
   (do not fetch again on every rapid pause/resume); Sunday always includes the
   next-week refresh described below. A changed response triggers another
   reconciliation. No `BapUApp` restructuring is needed. **Confirmed policy:
   one hour.** Compare the canonical current-week cache's successful write time
   with the resume instant and skip another current-week network refresh while
   it is at most one hour old. The payload must also identify the KST week
   containing the resume instant; a recently written response for another week
   is not fresh. In-flight resume refreshes are deduplicated. This is an
   operational freshness policy, not an iOS delivery guarantee.
   Reconciliation itself still runs on every resume even when network refresh
   is throttled, because it is the only planned repair for pending requests
   pinned before a device-timezone or locale change. Resolve the locale once
   at the start of each reconciliation so one batch cannot mix languages.
   Resume is also the only repair for an authorization change made in the
   Settings app: the status read at the head of reconciliation rebuilds the
   batch after a re-grant. A revocation leaves the existing requests pending
   and inert (§ Authorization) and updates the settings UI state.

   The implementation keeps this ownership in `AppSettings`: it registers and
   disposes the injectable `AppLifecycleListener`, rechecks authorization and
   performs cache-only reconciliation on every iOS resume, then applies the
   one-hour network policy. Raw current/next cache payloads, rather than file
   timestamps, are the stable content revisions used to decide whether a
   completed refresh needs a second reconciliation.
   `HomePage` and this resume path both opt into the same canonical foreground
   meal-refresh single-flight in `meal_data_source.dart`, so a KST week-boundary
   resume does not issue two current-week requests. Only the iOS Home/resume caller opts
   into waiting for Sunday next-week prefetch; Android and Web retain the old
   non-waiting foreground behavior. Metadata and dated-week preview requests do
   not participate because their prefetch/wait semantics differ and must not
   weaken a Sunday canonical refresh.
4. **Successful foreground meal refresh** — after validated current-week or
   next-week data is written, compare the raw payload/content revision with
   the prior cached revision. When it changed, force **notification
   reconciliation**, not another network refresh. The implementation compares
   the stable raw cache revisions and then reconciles from the validated cache
   snapshot. This intentionally performs a local cache read instead of carrying
   the parsed response across generations: an overlapping refresh may have
   committed newer data after that response returned. It never starts a second
   network request merely to rebuild notifications.
5. **Background meal refresh (iOS only)** — after
   `refreshBackgroundMealAndInfoCaches` successfully refreshes the cache, run
   the same cache-only reconciliation. Keep an explicit iOS platform guard so
   the shared Android background path does not start re-registering all
   Android one-off tasks every hour. Initialize the notification plugin in the
   background isolate without requesting permission — with the
   `request*Permission: false` change above, `initNotifications()` is safe to
   call here directly. Reading the authorization status is fine from the
   isolate; *prompting* belongs to the foreground UI flow only.

All iOS pending-request mutations, including foreground reconciliation,
master-disable/reset cancellation, and background reconciliation, share a
dedicated atomic exclusive-create marker in the app-support directory through
the repository's existing `withSharedWidgetFileLock` primitive. This is
cross-isolate rather than a process-local Dart mutex. Advisory
`RandomAccessFile.lock` is deliberately not used because macOS/iOS locks are
process-level and do not exclude isolates in one process. The existing
primitive's conservative two-second acquisition timeout and owner-only cleanup
remain: it never steals a same-PID marker and surfaces contention instead of
risking concurrent pending mutation. The lock timeout is shorter than a worst-
case 64-request plugin batch, so the lock alone is not the convergence
mechanism. Foreground setting changes await their `SharedPreferences` write and
advance a persisted notification-mutation generation before attempting the
lock. Background enters the lock, reloads uncached preferences plus current and
next raw-cache revisions, applies that snapshot, then reloads them again before
release. If any input changed, it applies the newer snapshot in the same
exclusive section (bounded to three attempts); disabled means canceling all
owned pending requests. Continued instability throws so Workmanager observes a
failure instead of reporting a stale success. Thus a foreground disable that
times out behind a long older background batch still converges: the background
sees the already-persisted generation and cancels before release. If foreground
acquires first, a later background batch reloads the persisted disabled state
and cannot re-add requests.

### Sunday next-week refresh

Sunday-night notifications target Monday breakfast, so next-week freshness is
the most important boundary. The existing `MealRefreshService` already
refreshes a matching next-week cache again on Sunday when it has not yet been
written that Sunday. Preserve and use that behavior:

1. On an app launch/resume or successful periodic refresh on Sunday, wait for
   next-week prefetch to finish.
2. If the next-week payload changed, rebuild the affected pending notifications
   immediately from the newly returned `WeekMeal`.
3. Keep the previously scheduled local notification as the delivery mechanism.
4. Treat the existing periodic BGAppRefresh as a best-effort Sunday top-up; do
   not add another Workmanager one-off timer. `earliestBeginDate` is not a
   deadline, so iOS may run the refresh after the configured alert time or not
   during that window at all.

The Sunday exception is narrower than "fetch on every Sunday resume": when the
next-week cache already identifies the expected next KST week and was written
on the current KST Sunday, the normal one-hour current-week throttle applies.
Otherwise resume waits for `MealRefreshService`'s existing next-week prefetch
even if the current-week cache is less than one hour old. Concurrent resume
callbacks still share one in-flight refresh.

The accepted product policy is **availability first**: if neither the app nor
BGAppRefresh runs on Sunday, deliver the notification computed from the latest
available next-week cache. It may be stale, but it is not silently dropped.
If the product later chooses accuracy first, schedule Monday-related alerts
only from a cache refreshed on Sunday and accept missed alerts when no refresh
runs.

There is no local-notification API that executes Dart or performs a network
request immediately before delivery. A hard requirement for fire-time-fresh
content would require a server-side visible APNs design. Silent push is still
opportunistic and does not provide that guarantee, especially after the user
force-quits the app.

### File-by-file changes

- **`notification_settings_store.dart` (new) and
  `notification_settings.dart`**: move preference defaults and legacy
  migration out of both `AppSettings._loadNotification` and the Android worker
  into one store function returning `NotificationSettings`. Keep the pure
  delivery-settings normalizer with the settings model; it derives effective
  cafeteria/dorm selections and owns the Debug/Release keyword gate. Both
  platforms must enter content generation through these shared functions.
- **`meal_notification_content_builder.dart` (new)**: own the pure cafeteria,
  dorm meal type, optional-keyword, localization, section, and per-group
  title/body construction. Android execution and iOS precomputation both call
  this function with a normalized delivery-settings snapshot.
- **`notification_scheduler.dart`**: keep the shared fire-time/target-date
  functions and Android Workmanager implementation. Add
  `fireInstantForTarget` with an injectable local-time factory. Dispatch iOS
  scheduling without importing `dart:io` into a file compiled for Web; use a
  Web-safe platform abstraction or conditional implementation.
- **iOS meal scheduling implementation**: own
  `buildMealNotificationBatch`, week loading, deterministic ID
  ownership, and pending-request reconciliation. Accept a complete immutable
  settings snapshot and injectable week loaders/plugin operations.
- **`notification_service.dart`**: add
  `scheduleMealNotification({id, fireInstant, title, body,
  DarwinNotificationDetails? notificationDetails})` and owned pending-request
  list/cancel helpers here (it owns the private `_plugin` instance already).
  Call through
  `resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()!
  .zonedSchedule(...)` rather than the top-level API, which forces an
  irrelevant `androidScheduleMode` argument.
  Flip `DarwinInitializationSettings`' three `request*Permission` flags to
  `false` so `initNotifications()` becomes background-safe registration only,
  and add a thin `mealNotificationAuthorizationStatus()` wrapper over
  `IOSFlutterLocalNotificationsPlugin.checkPermissions()` returning the
  three-state result defined in § Authorization (enabled / not authorized / not
  applicable) for reconciliation and the settings UI. Keep
  `requestNotificationPermission()` as the single
  foreground prompt entry point. Apply the § Delivery presentation decision by
  passing `interruptionLevel` through the `DarwinNotificationDetails` used for
  scheduled meal requests, and keep it consistent with `showMealNotification`'s
  Android/immediate path.
- **`meal_notification_worker.dart`**: keep the meal one-off execution and
  self-rescheduling path for Android, but replace its direct preference
  derivation and local Release keyword gate with the shared settings loader and
  normalizer. After a successful iOS cache refresh,
  run cache-only pending reconciliation. Do not add legacy iOS task cleanup or
  callback-suppression code: the feature has not shipped, and the new iOS path
  never registers meal-notification Workmanager one-offs.
  The Phase 2 background hook runs only after the meal refresh succeeds,
  explicitly guards for iOS, initializes the plugin without prompting, loads
  the latest persisted settings, and performs cache-only reconciliation.
  Android continues through its existing behavior without this hook.
- **`app_settings.dart`**: wire the four unwired mutators (trigger #2); add
  the injectable lifecycle registration (trigger #3). Master disable must
  cancel iOS meal pending requests immediately, and `resetAll()` must explicitly
  enter the same iOS owned-pending cancellation path. Keep Android Workmanager
  cancellation and iOS pending-notification cancellation as distinct platform
  operations rather than making `cancelMealNotificationFor` silently return
  on iOS. Make `setNotificationEnabled(true)` request authorization through an
  injectable permission-requester (so tests need no platform channel), and
  expose the resulting authorization state as observable settings state for the
  UI rather than swallowing a denial.
  Phase 2 also owns the injected resume-listener disposer, deduplicated one-hour
  foreground refresh, Sunday exception, and stable raw current/next cache
  revisions described above.
- **`main.dart`**: `initNotifications()` at line 52 must no longer prompt.
  Leaving cold-start registration in place is correct — only the prompt moves
  to the opt-in flow. Note the consequence for trigger #1: on a fresh install
  the launch reconciliation now runs with *not authorized*, so that state must
  be a scheduling no-op rather than a surfaced error. Beyond this
  and the trigger #1 rename, no other change is required here.
- **notification settings UI
  (`lib/features/settings/notification/`)**: render the combined
  not-authorized state with neutral persistent copy and a route into OS settings
  via the existing `app_settings` package dependency. New user-facing strings go into
  `lib/l10n/app_ko.arb` and `app_en.arb`, not inline literals.
- **foreground meal-refresh orchestration**: after a successful changed meal
  response/cache write, request iOS reconciliation with the returned data.
  Avoid a dependency from the meal data layer back into the notification UI
  layer and avoid starting a second fetch merely to rebuild notifications.
- **next-week preview orchestration**: the successful dated-week load already
  returns the parsed response after writing `meal-next.json`. Notify
  `AppSettings` from that UI orchestration point; it compares the stable cache
  revision and requests cache-only iOS reconciliation without another fetch.
- **`pubspec.yaml`**: promote `timezone` to a direct dependency.

The new shared content builder and platform-specific scheduler are intentional
seams, not duplicate architecture: they prevent private worker logic from
being copied and keep iOS orchestration out of the Web-compiled scheduler.

### Delivery phases

Implement and verify this in two independently shippable phases.

**Phase 1 — reliable iOS delivery (required for release)**

- first prove a near-term `Etc/UTC` one-shot delivery on an iOS simulator; use
  the named-device-timezone fallback above if that gate fails;
- move the authorization prompt off cold start onto the notification opt-in,
  make the authorization status an explicit reconciliation precondition, and
  surface a denial in the settings UI (§ Authorization) — a Phase 1 that
  schedules correctly into a denied state ships nothing the user can perceive;
- settle the § Delivery presentation decision and apply the resulting
  `interruptionLevel` (or record acceptance of summary batching);
- centralize preference loading/migration and effective delivery-settings
  normalization so Android and iOS cannot interpret the same stored state
  differently;
- extract the shared localized content builder;
- add `fireInstantForTarget`, the batch builder, deterministic IDs,
  whole-slot cap truncation, lead-time filtering, and iOS `zonedSchedule`
  reconciliation;
- connect app launch, completion of the normal initial foreground meal fetch,
  master enable/disable, and all notification-setting mutators;
- delete the old iOS Workmanager registration path, with no migration code;
- keep Android's existing Workmanager path and verify it is unchanged;
- surface scheduling failures in Release and complete unit plus simulator QA.

This phase fixes the structural delivery failure for requests that fit in the
scheduled horizon, including a first install with no cache because the normal
initial foreground fetch feeds reconciliation. It must not claim indefinite
delivery after force-quit for dense configurations whose desired requests
exceed the iOS pending limit.

**Phase 2 — freshness and lifecycle hardening**

- add every-resume reconciliation and the explicit foreground refresh
  staleness policy, including the resume-time authorization re-check that
  repairs a grant/revocation made in the Settings app;
- reconcile after subsequent changed foreground meal responses;
- add iOS-only background-refresh reconciliation;
- add Sunday next-week refresh/top-up behavior;
- prevent older launch/resume/background generations from overwriting newer
  settings or meal revisions;
- complete real-device BGAppRefresh, timezone-change, and locale-change QA.

Phase 2 reduces stale content and repairs timezone drift. Deferring it does not
reintroduce the old Workmanager delivery failure, but Phase 1 alone can retain
stale content longer and keeps an already-scheduled absolute instant/text until
the next app launch after a device-timezone or locale change.

The generation guard is carried from `NotificationScheduleCoordinator` into
the iOS reconciler. A superseded operation checks it after asynchronous reads
and before each pending cancellation/upsert, while the coordinator serializes
platform mutations and reports the old request as superseded. This covers
overlapping launch/resume/settings/foreground-refresh requests in the main
isolate. The background entry does not carry a foreground snapshot: after its
successful refresh it runs the bounded stable-snapshot loop above under the
cross-isolate mutation marker. This persisted-generation recheck covers the
case where foreground lock acquisition times out behind a long plugin batch.

### Testing strategy

Mirror the existing typedef-injection pattern from
`notification_scheduler_test.dart` / `meal_notification_worker_test.dart`
(no platform channel mocking):

- `fireInstantForTarget` round-trip property test across periods × dates ×
  injected device UTC offsets (§ above), plus calendar/DST boundaries — this
  is the test that catches the actual timezone inversion bug class.
- `buildMealNotificationBatch`: empty keywords → one request per selected
  non-empty meal group; multiple groups at one fire slot have unique IDs;
  >cap candidates → deterministic chronological whole-slot truncation;
  day-of-week and minimum-lead-time filtering; reserved ID-range ownership.
- settings-to-content parity starts from raw preference states, not an already
  normalized settings input: cover absent cafeteria/type keys, student-only,
  dormitory plus student, explicit dormitory meal types, and legacy keys; then
  verify Android and iOS derive identical effective delivery settings and
  per-group content for the same target date, period, locale, and `WeekMeal`.
  Inject both keyword-filter-enabled states so the production Release gate is
  tested in the shared normalizer rather than separately per caller.
- Korean/English content: localized cafeteria/meal/title text, `/`-separated
  single-line bodies, English menu fallback to Korean, and Release forcing an
  empty keyword list. Resolve `[unsupported, ko]` to Korean just like the app,
  rather than looking only at the first device locale.
- iOS reconciliation with injected scheduler/canceler/pending-request fakes and
  week loaders: current-week failure during a data refresh → preserve old
  requests; next-week failure → reconcile the current range while retaining
  existing next-week requests; success → stale owned IDs in both loaded
  ranges removed and desired deterministic IDs upserted.
- fail the Nth `zonedSchedule` call and verify that the error is surfaced and
  the resulting partial state is bounded/retryable.
- use `package:clock`'s `withClock()` to advance time between batch build and
  an individual upsert: a candidate that became strictly past is skipped,
  equality remains valid like the plugin, and an `ArgumentError` for a
  still-future candidate is rethrown rather than hidden.
- authorization gating with an injected status reader: not-authorized
  → no cache read, no batch build, **no pending-request mutation**, and the
  caller sees that state rather than a success; not-applicable (`null`) →
  reconciliation proceeds normally; a not-enabled→enabled transition between two
  reconciliations rebuilds the full batch from the still-present requests'
  reserved ID range.
- `setNotificationEnabled(true)` calls the injected permission requester exactly
  once, and a denial is exposed as observable settings state instead of being
  swallowed.
- master disable and `resetAll` immediately remove iOS meal-notification pending
  requests without requiring meal data.
- a user restriction followed by a cache/network failure does not leave stale
  notifications based on removed settings.
- `AppSettings`: the four previously-unwired mutators now trigger a (fake)
  reschedule call when `notification.enabled`.
- **(Phase 2)** background refresh invokes reconciliation only on iOS; Android
  retains its existing one-off scheduling behavior.
- **(Phase 2)** overlapping launch/resume/background generations cannot let an
  older batch overwrite a newer settings or meal revision.
- **(Phase 2)** change the injected device timezone between reconciliations and
  verify the same configured wall-clock time maps to a newly scheduled
  absolute instant.
- Android delivery behavior stays unchanged; keep its existing suite green and
  extend parity coverage for the new shared settings path.

### Residual risk (accepted, not fully eliminated by more triggers)

Precomputed content can go stale relative to a live menu change between the
last successful recompute and fire time (outdated full-menu items, or a false
positive/missed match when the optional keyword filter is active).
Foreground refresh, change-triggered reconciliation, Sunday next-week refresh,
and opportunistic BGAppRefresh reduce this window but cannot eliminate it.
This is inherent to trading "live at fire time" (not reliably available on
iOS) for "live at last recompute" and is explicitly accepted under the
availability-first policy.

There is a distinct iOS-only omission risk when a menu group is empty at
precompute time. Because empty content creates no pending request, a menu
published later will produce no notification unless an app launch/resume,
successful foreground refresh, or opportunistic BGAppRefresh rebuilds the
batch first. This is a missed notification, not merely stale text, and the
availability-first policy only preserves requests that existed at precompute
time. Do not reserve placeholder requests in this migration: they consume the
same 64-request budget and could deliver non-menu text. Record this limitation
explicitly and rely on the documented recompute triggers; revisit placeholder
or server-push policy only if product requirements change.

`UNUserNotificationCenter` also has no atomic multi-request transaction. A
mid-batch platform failure can leave a partial horizon until the next retry;
failures must therefore be observable in Release rather than assert-only.

Presentation timing is not under the app's control. The accepted `.active`
level means iOS Scheduled Summary and Focus modes may hold a correctly-fired
request and present it in a later summary window. Keep release notes, settings
copy, and QA from describing the configured alert time as a presentation
guarantee.

The pending-request cap creates a second accepted residual risk. When selected
periods × meal groups exceed the available horizon, later notifications depend
on a future launch/resume or opportunistic BGAppRefresh to replenish the batch.
No additional local trigger can remove this OS capacity limit. The UI need not
restrict choices in this migration, but release notes/QA must not describe the
maximum configuration as long-horizon guaranteed delivery.

## Verification

- Unit tests above run via `flutter test test/features/notification/`
  (existing files extended, no new test files required).
- `zonedSchedule` delivery itself is testable on iOS **simulator** by
  scheduling a near-term (~1 min) test notification through the new
  `notification_service.dart` function and confirming delivery while the
  app is backgrounded/killed. This must use the proposed `tz.UTC` path and
  confirm that native `Etc/UTC` lookup succeeds before the remaining Phase 1
  implementation relies on it. Unlike BGAppRefreshTask, this does not require
  a real device.
  The current implementation was produced and automatically verified on
  Windows, so this simulator gate remains explicitly outstanding and must not
  be reported as passed until it is run on macOS.
- The same simulator gate confirms the § Authorization premise at near-zero
  extra cost: on a fresh install, decline the authorization prompt, schedule one
  request, and read `pendingNotificationRequests()`. If the call succeeds and
  the request is listed while nothing is presented, the silent-failure framing
  is confirmed. If it instead fails loudly, record that and simplify the
  detection accordingly — the required changes are unchanged either way.
- Trigger #5 (BGAppRefreshTask actually firing) still requires real-device
  QA per Apple's own documented simulator limitation and belongs to Phase 2;
  it is not a blocker for the Phase 1 delivery replacement.
- Authorization QA needs a **fresh install** each time, because iOS shows the
  prompt only once per install: verify that first launch shows no prompt; that
  the prompt appears when the notification master switch is turned on; that
  declining it surfaces denial-specific transient feedback plus a persistent,
  neutrally worded route to OS settings instead of a silently-scheduled batch;
  that granting it in the Settings app afterwards
  and resuming the app rebuilds the horizon; and that revoking it there updates
  the settings UI on the next resume while leaving the (now inert) pending
  requests in place, so a later re-grant restores delivery without needing a
  successful cache read first.
- Presentation QA: with Scheduled Summary enabled for the app (and separately
  with a Focus mode active), confirm whether a meal notification arrives at its
  configured time or is held for the summary, and record the observed behavior
  against the § Delivery presentation decision.
- Manual QA checklist: enable notification → force-quit app → verify
  each selected cafeteria receives its own localized full-menu notification
  at the configured local time; verify its body is one `/`-separated line;
  switch the system/per-app language and resume → verify rebuilt titles,
  cafeteria labels, and menu fallback match the app; in Debug, edit a keyword
  → verify next-launch/foreground reschedule updates content; disable the
  master switch/period/day/cafeteria → verify owned
  pending notifications are removed immediately; refresh a changed next-week
  menu on Sunday → verify the existing Monday request is replaced; prevent the
  Sunday BG task from running → verify the documented availability-first stale
  fallback rather than claiming a fire-time refresh guarantee; precompute a
  slot while one selected group is empty, publish that menu without launching
  or refreshing the app, and verify/document that no request appears until a
  recompute trigger runs; change the
  simulator/device timezone, resume the app, and verify pending requests move
  back to the configured local wall-clock time. With several cafeterias
  selected near the cap, verify reconciliation retains or drops an entire fire
  slot rather than a partial cafeteria subset.
