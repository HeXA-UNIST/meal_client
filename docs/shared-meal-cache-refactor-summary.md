# Shared Meal Cache Refactor Summary

## Purpose

This refactor makes raw meal API JSON the single canonical cache source for the app, Workmanager background refresh, future local notifications, and future home-screen widgets.

Before this change, foreground meal loading fetched and cached data directly inside `meal_data_source.dart`, and planned notification/widget implementations were likely to add their own backend fetch paths. That would duplicate cache/freshness behavior and create branch conflicts.

After this change, feature code should consume `MealCache` and `MealRefreshService` instead of fetching `ApiConstants.mealEndpoint` directly.

## Main Changes

### KST Week Freshness

- Added `MealTimeConfig.kstWeekId(DateTime time)` in `lib/core/constants.dart`.
- Replaced the previous year-based week-number logic with a monotonic KST week ID anchored at Monday, 1970-01-05.
- Cache freshness still uses the existing product rule: a meal cache is fresh when the cache file `lastModified` belongs to the current KST menu week.

### Canonical Meal Cache

- Added `lib/features/meal/meal_cache.dart`.
- `MealCache` wraps the existing platform storage layer:
  - native: `getApplicationSupportDirectory()/meal.json`
  - web: no persistent cache; freshness returns `false` when storage metadata is unavailable
- The cache stores raw API JSON only. There is no wrapper JSON and no separate `updatedAt` metadata.

Public contract:

```dart
Future<void> writeRawMealJson(String rawJson);
Future<String> readRawMealJson();
Future<DateTime> getRawMealUpdatedAt();
Future<bool> hasFreshMealCache(DateTime now);
```

### Shared Refresh Service

- Added `lib/features/meal/meal_refresh_service.dart`.
- `MealRefreshService.refreshMealData()` always fetches the backend, validates/parses the raw JSON, writes only valid non-empty array responses to `MealCache`, and returns parsed `WeekMeal`.
- `MealRefreshService.getFreshOrRefreshMealData()` reads fresh cache first and falls back to backend fetch when the cache is stale, missing, or corrupt.

### Meal Data Source Rewrite

- Rewrote `lib/features/meal/meal_data_source.dart` from the owner of fetch/cache/freshness logic into a thin compatibility entry point for existing UI callers.
- `fetchAndCacheMealData()` now delegates to `MealRefreshService.refreshMealData()`.
- `getCachedMealData()` now delegates freshness and raw reads to `MealCache`, then parses the raw JSON into `WeekMeal`.
- This keeps `HomePage` imports stable while moving shared cache behavior into reusable services for notifications and widgets.

### Existing HomePage Behavior Preserved

`HomePage` still keeps the current UX:

- display cached meal data first when available
- always perform a foreground fresh fetch afterward

The implementation now routes through shared cache/refresh plumbing, but does not switch foreground app-open behavior to cache-only.

### Workmanager Background Refresh

- Added conditional background refresh files:
  - `meal_background_refresh.dart`
  - `meal_background_refresh_io.dart`
  - `meal_background_refresh_stub.dart`
- `main()` initializes background refresh after `WidgetsFlutterBinding.ensureInitialized()`.
- Native platforms register an hourly `bapu_meal_refresh` periodic task.
- Web uses a no-op implementation.
- The Workmanager callback is annotated with `@pragma('vm:entry-point')`.
- The background isolate initializes its own Flutter bindings before refreshing meal data.
- When notification evaluation is added, that dispatcher must also initialize `SharedPreferences` and construct `AppSettings` inside the background isolate before reading notification settings.
- Android registration uses `NetworkType.connected`; iOS does not receive an equivalent Workmanager network constraint because `BGAppRefreshTaskRequest` does not enforce it.

Current background task responsibility:

- refresh meal data into `MealCache`
- no widget MethodChannel calls
- no notification matching yet

### iOS Background Setup

- Updated `ios/Runner/AppDelegate.swift` to register Workmanager plugins for background isolates and register the periodic refresh identifier.
- The periodic task is registered directly because the project deployment target is iOS 14.0, so no iOS 13 availability guard is needed.
- Updated `ios/Runner/Info.plist` with:
  - `BGTaskSchedulerPermittedIdentifiers`
  - `UIBackgroundModes` fetch

iOS background execution remains best-effort and should not be treated as exact-timing notification infrastructure.
The `NetworkType.connected` constraint used for Workmanager registration is enforced by Android; iOS background refresh may still be attempted without the same network constraint semantics.

### Removed `home_widget`

- Removed unused `home_widget` dependency from `pubspec.yaml`.
- Refreshed `pubspec.lock`.
- This unblocked Android build failures caused by `home_widget` pulling AndroidX Glance dependencies requiring compileSdk 37 and Android Gradle Plugin 9.1.0.

### Native Android Widget Integration

- Rebasing onto `develop-widget` kept the native Android widget providers, config activities, layouts, and periodic widget worker.
- `BapUWidgetFetcher.fetch(context)` now reads `context.filesDir/meal.json` first, which is the same raw cache file written by Flutter on Android.
- Native widget cache freshness mirrors Dart by comparing file `lastModified` with the current time using the monotonic KST week ID rule.
- The existing native network fetch remains only as a fallback when the shared cache is missing, stale, or invalid, and successful fallback responses are parsed before being written back to `meal.json`.
- Widget update entry points now pass `Context` into `BapUWidgetFetcher` so providers, config screens, and `BapUWidgetUpdateWorker` all use cache-first loading.

### Cache Robustness

- Native Dart cache writes now use a temporary file and rename into place to avoid readers seeing a partially written `meal.json`.
- Cache freshness check failures are logged with stack traces before returning stale, so storage/plugin regressions are not silently reduced to cache misses.
- Foreground widget refresh MethodChannel failures are logged in release builds instead of only inside debug assertions.

### Android Desugaring

- Enabled core library desugaring in `android/app/build.gradle.kts`.
- Added `com.android.tools:desugar_jdk_libs:2.1.4`.
- Required by `flutter_local_notifications` 21.0.0.

## Tests Added

- KST week ID boundary tests in `test/domain_test.dart`.
- `MealCache` tests in `test/features/meal/meal_cache_test.dart`.
- `MealRefreshService` tests in `test/features/meal/meal_refresh_service_test.dart`.

Covered behavior:

- same KST week across UTC/year boundary
- Monday and Sunday in the same KST week produce the same ID
- Monday 00:00 KST week rollover
- Jan 1 Sunday edge case
- raw JSON write/read contract
- fresh/stale cache detection using file `lastModified`
- web/no-cache-style metadata failure returns stale
- fresh cache avoids network fetch
- stale cache fetches and stores backend response
- corrupt fresh cache falls back to backend fetch

## Verification

Passed:

```bash
flutter analyze                  # no issues
flutter test                     # 56 tests passed
flutter build apk --debug         # built app-debug.apk
```

APK output:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

The Android build still prints future deprecation warnings for Gradle 8.13.0 and Kotlin 2.1.0, but they are not current build blockers.

## Integration Guidance

### Local Notification Branches

Notification code should not call `fetchRawString(ApiConstants.mealEndpoint)` directly.

Use:

```dart
final meal = await MealRefreshService().getFreshOrRefreshMealData();
```

Then evaluate `AppSettings.notification` against that `WeekMeal`.

If a notification branch already added direct backend fetching, replace that fetch path with `MealRefreshService`.

### Widget Branches

Widgets should use the shared raw `meal.json` cache as their data source.

For Android native widgets, read the same app-internal raw JSON file and apply the same KST freshness rule using file `lastModified`. Native Kotlin should mirror the monotonic KST week ID logic.

For future iOS WidgetKit, move the physical storage location behind `MealCache` if an App Group container is needed. Keep the payload format the same raw meal API JSON instead of introducing a separate widget-only cache format.

## Remaining Follow-Ups

- Implement notification matching/showing on top of `MealRefreshService`.
- Revisit iOS background behavior when notification timing requirements are finalized.
- Reintroduce a widget package or native widget implementation only after choosing a dependency/toolchain path compatible with the project Android Gradle setup.
- Eventually address Flutter warnings about Gradle and Kotlin versions.
