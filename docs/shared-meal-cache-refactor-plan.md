# Shared Meal Cache Refactor Plan

## Summary

This plan starts from `develop` (`0599c81`), where notification/widget packages and settings UI exist, but there is no notification service, no Workmanager initialization, and no native Android widget implementation yet.

The refactor creates one canonical raw meal cache used by the app today and by future local notifications and home widgets. Fetching should be centralized in Dart app/background refresh code; notifications and widgets should read cached data instead of each implementing direct backend fetches.

## Current `develop` Baseline

- `fetchAndCacheMealData()` fetches `ApiConstants.mealEndpoint`, writes raw JSON to `StorageKeys.mealCacheFile`, and parses it.
- `getCachedMealData()` reads the same file and checks freshness with `_getKstWeekNumber`, which still has the known KST/year-boundary bug.
- Native cache storage is currently `getApplicationSupportDirectory()/meal.json`.
- `flutter_local_notifications`, `workmanager`, and `home_widget` are present in `pubspec.yaml`, but none are wired.
- Notification and widget settings are UI/state placeholders only:
  - notification: enabled, keyword, alert time, cafeterias
  - widget: cafeteria, meal of day

## Phase 1: Fix Shared Freshness Primitive

- Implement `docs/kst-cache-bugfix-spec.md` first or in the same branch.
- Move the monotonic KST week ID helper to a shared Dart location, preferably `lib/core/constants.dart` near `MealTimeConfig`, so tests and cache code can use it.
- Replace `_getKstWeekNumber` in `meal_data_source.dart` with the monotonic KST week ID.
- Keep the v1 freshness rule unchanged in product terms: cache is fresh when its file `lastModified` is in the current KST menu week.

## Phase 2: Introduce Canonical Meal Cache

- Add a Dart `MealCache` abstraction for raw API JSON:
  - `Future<void> writeRawMealJson(String rawJson)`
  - `Future<String> readRawMealJson()`
  - `Future<DateTime> getRawMealUpdatedAt()`
  - `Future<bool> hasFreshMealCache(DateTime now)`
- Implement `MealCache` as a concrete Dart class or static utility that wraps the existing `storage.dart` conditional export. Do not add another platform conditional export in v1.
- Use file `lastModified` as the only v1 timestamp source. Do not add an optional `updatedAt` parameter and do not wrap the raw API JSON.
- Keep the existing Android/iOS file-backed behavior for now by delegating to the current `storage_io.dart` implementation.
- Keep web as no persistent cache, matching the current `storage_web.dart` behavior. `MealCache.hasFreshMealCache(DateTime now)` must return `false` on web or when `getRawMealUpdatedAt()` throws, so web always behaves as stale and refreshes from the backend.
- Update `fetchAndCacheMealData()` to fetch raw JSON, write through `MealCache`, then parse that same raw string.
- Update `getCachedMealData()` to call `MealCache.hasFreshMealCache(DateTime.now())`, then parse `MealCache.readRawMealJson()`.

## Phase 3: Add Shared Refresh Service

- Add `MealRefreshService` as the one Dart entrypoint for background/app refresh:
  - `Future<WeekMeal> refreshMealData()` fetches API, writes `MealCache`, and returns parsed `WeekMeal`.
  - `Future<WeekMeal> getFreshOrRefreshMealData()` reads cache if fresh, otherwise refreshes.
- Update `HomePage` to preserve current app-open behavior exactly: keep cached data first, then always call `MealRefreshService.refreshMealData()` for the fresh `downloadedMeal` future. Do not replace the foreground fresh fetch with `getFreshOrRefreshMealData()`, because that would stop automatic updates on app open when the cache is still considered fresh.
- Do not add notification matching or widget rendering in this phase. This branch is the foundation other feature branches rebase onto.

## Phase 4: Workmanager Integration Contract

- Register Workmanager in `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
- Annotate the Workmanager callback dispatcher with `@pragma('vm:entry-point')` so it survives release tree shaking.
- Add a background dispatcher with one cache refresh task name, such as `bapu_meal_refresh`.
- Register it as a periodic task with `const Duration(hours: 1)` for v1. This is above Android WorkManager's 15-minute minimum and keeps backend traffic conservative; notification branches can later revisit this if product latency requires it.
- The Dart Workmanager task should only:
  - call `MealRefreshService.refreshMealData()`
  - later call notification evaluation once the notification service exists
- Because Workmanager runs in a separate Dart isolate, any later notification evaluation must initialize its own dependencies inside the callback:
  - call `WidgetsFlutterBinding.ensureInitialized()`
  - get `SharedPreferences.getInstance()`
  - construct `AppSettings(prefs)` or a smaller settings reader
  - then evaluate notification settings against cached/refreshed meal data
- Do not call UI-bound APIs or `MethodChannel` widget refresh from the Workmanager background isolate.
- Treat iOS Workmanager execution as best-effort. Do not design notification correctness around exact iOS background timing.

## Notification Branch Integration

- Local notification branches should not call `fetchRawString(ApiConstants.mealEndpoint)` directly.
- Notification code should use this flow:
  - call `MealRefreshService.getFreshOrRefreshMealData()` when it needs current menu data
  - evaluate `AppSettings.notification` against the returned `WeekMeal`
  - schedule/show notifications through the notification service
- Keep notification settings in `AppSettings`; do not move them into `MealCache`.
- If another branch already implemented direct backend fetches, adapt it after rebasing by replacing the direct fetch with `MealRefreshService`.

## Widget Branch Integration

- On `develop`, there is no native widget implementation yet. Treat widget integration as a later consumer of `MealCache`.
- Android native widgets can read the same raw cache file from app-internal storage. The Android fallback API URL must stay in sync with `ApiConstants.mealEndpoint`.
- If using the `develop-widget` native Android implementation later:
  - replace direct native API fetches with cache-first loading
  - return native `WidgetMealData?` from the widget repository, not Dart `WeekMeal`
  - fall back to native network fetch only when cache is missing, stale, or invalid
  - mirror the Dart monotonic KST week ID in Kotlin using file `lastModified`
- For future iOS WidgetKit, move the same raw `meal.json` storage behind the `MealCache` abstraction to an App Group container. Do not create a separate iOS widget cache format.

## Branch Conflict Strategy

- Recommended merge order:
  1. `fix/kst-week-id`
  2. `refactor/shared-meal-cache`
  3. local notification feature branches rebased onto shared cache
  4. widget feature branches rebased onto shared cache
- Keep the shared cache branch focused on cache/refresh plumbing only. Do not implement notification behavior or widget UI there.
- Publish `MealCache` and `MealRefreshService` as the stable integration contract for other branches.
- When resolving notification branch conflicts, prefer deleting branch-local API fetch helpers and routing through `MealRefreshService`.

## Test Plan

- Dart unit tests:
  - monotonic KST week ID boundaries, including Monday 00:00 KST and Jan 1 Sunday cases
  - `MealCache` writes raw JSON and reads the same raw JSON
  - `MealCache.hasFreshMealCache` uses file `lastModified` and the shared KST week ID
  - `MealCache.hasFreshMealCache` returns `false` when `getRawMealUpdatedAt()` throws, covering web/no-cache behavior
  - `fetchAndCacheMealData()` writes cache and returns parsed `WeekMeal`
  - `getCachedMealData()` throws on stale/missing cache and parses valid cache
  - `MealRefreshService.getFreshOrRefreshMealData()` prefers fresh cache and refreshes stale cache
  - `HomePage`/data-loading behavior still performs an unconditional foreground refresh after showing cached data
- Regression checks:
  - `flutter analyze`
  - `flutter test`
  - Android debug build after Workmanager wiring
- Later widget branch checks:
  - Android widget renders from cache with network disabled after app/background refresh
  - Android widget falls back to network only when cache is missing/stale/invalid

## Assumptions

- Raw meal API JSON remains the canonical cache format.
- File `lastModified` is the only v1 cache timestamp source.
- Weekly KST invalidation remains the product behavior after fixing the week ID calculation.
- Workmanager is acceptable as the shared background refresh mechanism, but iOS timing is best-effort.
- Notification and widget feature work should become consumers of `MealCache` and `MealRefreshService`, not owners of separate backend fetch/cache flows.
