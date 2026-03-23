# BapU Architecture Analysis

> Software engineering analysis of the `meal_client` codebase.
> Written 2026-03-17. Code is **not** modified here — this is a read-only analysis.

---

## 1. Layer Overview

The project is organized into three loosely-defined layers. There is no explicit architecture boundary (no repository pattern, no use-case layer), but the separation of concerns is reasonable for a small app.

```
┌─────────────────────────────────────────────────────┐
│  UI Layer                                           │
│  pages/home/home_page.dart                          │
│  pages/home/home_app_bar.dart                       │
│  pages/home/week_meal_view.dart                     │
│  pages/home/meal_card.dart                          │
│  pages/home/nested_page_scroll.dart                 │
│  pages/home_drawer.dart                             │
├─────────────────────────────────────────────────────┤
│  State / Domain Layer                               │
│  model.dart           — BapUModel (global state)   │
│  meal.dart            — domain data classes         │
│  string.dart / i18n.dart — localization primitives  │
├─────────────────────────────────────────────────────┤
│  Data / Infrastructure Layer                        │
│  api_v2.dart          — HTTP + JSON parsing         │
│  data.dart            — cache orchestration         │
│  storage.dart (+ _io / _web) — file I/O             │
│  platform_http_client.dart (+ _io / _web) — HTTP    │
└─────────────────────────────────────────────────────┘
```

The UI layer bypasses the domain layer and directly imports `api_v2.dart` and `data.dart` from `home_page.dart`. There is no repository or service object separating data access from UI.

---

## 2. Theme / Dark Mode

### Current approach

`BapUModel` stores `Brightness _themeBrightness`. A `Consumer<BapUModel>` at the root (`MyApp.build`) rebuilds the entire `MaterialApp` — including its `ThemeData` and `ColorScheme` — whenever brightness changes. The platform brightness is forwarded by a callback registered in the Provider's `create:` function inside `main()`.

```dart
// main.dart — platform side-effects inside Provider factory
platformDispatcher.onPlatformBrightnessChanged = () {
  model.setThemeBrightness(platformDispatcher.platformBrightness);
};
```

### Issues

**a. Non-idiomatic theme pattern.**
Flutter's `MaterialApp` has built-in `themeMode` and `darkTheme` parameters designed exactly for this purpose. The standard pattern:

```dart
MaterialApp(
  themeMode: ThemeMode.system,   // follows system setting automatically
  theme: lightThemeData,
  darkTheme: darkThemeData,
)
```

With this pattern, Flutter internally swaps themes without rebuilding `MaterialApp`. The current approach rebuilds `MaterialApp` (and therefore the entire subtree below it) on every brightness change.

**b. Side effects in a Provider `create:` callback.**
The `create:` parameter is a factory — its purpose is to create the model object. Registering `PlatformDispatcher` callbacks inside it is a side effect that is invisible at the call site and makes the initialization order implicit. Callbacks like `onPlatformBrightnessChanged` belong in an `initState`-like lifecycle method, not in object construction.

**c. `BapUModel` mixes two unrelated concerns.**
Language preference and theme brightness are independent application-level settings. They are currently combined in one `ChangeNotifier`, so a brightness change triggers any consumer that listens for language changes and vice versa, even if only one value changed. Because `notifyListeners()` is coarse-grained, all `Consumer<BapUModel>` widgets rebuild on any change to either field.

**d. Manual `ColorScheme.copyWith` overrides on every build.**
`surface` and `surfaceContainer` are overridden with hardcoded `Color.fromARGB` literals on every `MaterialApp` rebuild. These are frozen design decisions masquerading as dynamic calculations.

---

## 3. Internationalization / Language

### Current approach

A custom `MultiLanguageString` class holds `eng` and `kor` fields. Every call site passes a `Language` value and calls `.getLocalizedString(language)` manually. The `Language` enum is threaded explicitly through the widget tree as a parameter. Language detection in `main.dart` is permanently disabled:

```dart
if ( /* platformDispatcher.locale.languageCode == "ko" */ true) {
  language = Language.kor;
}
```

The same disabled condition appears twice (lines 21 and 39 of `main.dart`).

### Issues

**a. Language switching is completely disabled.**
The `onLocaleChanged` callback is wired up and `BapUModel.changeLanguage` is implemented, but the detection condition is commented out and replaced with `true`. The infrastructure exists but is permanently short-circuited. A future developer might not notice the commented-out condition.

**b. Non-idiomatic localization.**
Flutter's standard approach (`flutter_localizations` + `intl` + `.arb` files) provides:
- Compile-time key safety
- Pluralization and gender rules
- Date/number/currency formatting via `intl`
- Proper locale inheritance via `Localizations.of(context)`
- Tooling support (extraction, translation workflows)

The current `MultiLanguageString` pattern requires every widget that needs a localized string to accept a `Language` parameter, coupling widget interfaces to the localization mechanism. Adding a third language requires touching every `MultiLanguageString` definition site.

**c. `language` is manually threaded through the widget tree.**
Widgets like `WeekMealTabBarView`, `DayOfWeekTabBar`, `AnimatedDateTitle`, `_OperationHoursSection`, and `HomePageDrawer` all accept `Language` as a constructor parameter. This is equivalent to prop-drilling. The standard Flutter alternative is `Localizations.of(context)` or a dedicated `Consumer`/`context.read`.

**d. Date formatting is hand-rolled in `string.dart`.**
`getLocalizedDate()` is a 30-line switch statement that re-implements what `intl`'s `DateFormat` does in one line. Month names are hardcoded as `MultiLanguageString` constants. This will not handle locale-specific date ordering (e.g., Korean uses year-month-day) correctly if the language list grows.

**e. `string.dart` mixes data with logic.**
String constants and the `getLocalizedDate()` function live in the same file. The function is a date-formatting utility, not a string constant, and belongs in a separate utility or in the domain layer.

---

## 4. State Management

### Current approach

`BapUModel` (global, Provider `ChangeNotifier`) holds language and brightness. `HomePageModel` (local, plain mutable class) holds the current `MealOfDay` and `DayOfWeek`. `_HomePageState` owns `HomePageModel` and mutates it via `setState()`.

### Issues

**a. `HomePageModel` is neither immutable nor a `ChangeNotifier`.**
It is a plain mutable class whose fields are directly assigned. All mutations are wrapped in `setState()` at the `_HomePageState` level. This pattern works but is semantically unclear: `HomePageModel` looks like a data holder but acts as a state object. It should either be a simple immutable record (fields moved directly into `_HomePageState`) or a proper `ChangeNotifier`.

**b. Transition guard state (`_isMealOfDayButtonTransition`) is an ad-hoc flag.**
This boolean prevents `onPageChanged` from overwriting button state during a programmatic page animation. The underlying issue is that the button-initiated transition and the swipe-initiated transition share the same `onPageChanged` callback without a way to distinguish their origin. A state machine (e.g., an enum `_TransitionSource { none, button, swipe }`) would be more explicit.

**c. `BapUModel` side effects in construction (repeated from §2b).**
The `PlatformDispatcher` callbacks are set up during Provider `create:`, not in a lifecycle method. This is a form of implicit initialization that is hard to test or mock.

---

## 5. Domain / Data Model

### Issues

**a. Enum-indexed data uses named fields instead of collections.**
`WeekMeal` has seven named fields (`mon`, `tue`, ..., `sun`). `DayMeal` has three (`breakfast`, `lunch`, `dinner`). `CafeteriaMeal` has three (`dormitory`, `student`, `faculty`). Access is via manually-written `switch` statements in `fromDayOfWeek()`, `fromMealOfDay()`, and `fromCafeteria()`.

Since `DayOfWeek`, `MealOfDay`, and `Cafeteria` are enums with consecutive integer indices, these classes could instead use `List<T>` indexed by `enum.index`, or Dart's `EnumMap`-style pattern. As it stands, adding a new cafeteria requires updating both the `Cafeteria` enum and every switch statement.

**b. `empty()` constructors return partially-mutable objects.**
`CafeteriaMeal.empty()` initializes `dormitory`, `student`, and `faculty` with `List.empty(growable: true)`. The `final` keyword on the fields prevents reassigning the list reference, but the list contents are mutable. `parseRawMeal()` in `api_v2.dart` exploits this to build the model by appending to those lists. This means the model is mutable during construction but is treated as immutable afterward — an implicit two-phase initialization.

A cleaner design would parse into intermediate builder structures and then construct immutable model objects in one step.

**c. Inheritance used as a type tag.**
`KoreanMeal` and `HalalMeal` extend `Meal` without adding any fields or methods. Their only purpose is to let calling code distinguish meal types via `case KoreanMeal _:` pattern matching. Dart sealed classes or an enum field on `Meal` (e.g., `MealType? type`) would express this intent more directly.

**d. `nextMealOfDay()` and `nextDayOfWeek()` are top-level functions.**
These are logically operations on their respective enums and would be more discoverable as extension methods:

```dart
extension MealOfDayExt on MealOfDay {
  MealOfDay get next { ... }
}
```

---

## 6. API / Network Layer

### Issues

**a. API key is Korean-language text.**
`parseRawMeal()` switches on `meal["restaurantType"]` with Korean string literals (`"기숙사 식당"`, `"학생 식당"`, `"교직원 식당"`). If the API changes its Korean representation, parsing silently throws a `FormatException`. An API-level constant or a mapping table would be more robust.

**b. Global mutable HTTP client.**
`_httpClient` is a module-level `final` in `api_v2.dart`. This is a global singleton, which makes unit testing impossible without dependency injection. A cleaner design would accept the client as a parameter or inject it via the Provider tree.

**c. Untyped error handling.**
All network errors are thrown as generic `Exception("HTTP ...")`. The caller in `data.dart` catches all exceptions to decide cache validity. Typed error classes (`NetworkException`, `ParseException`, `CacheExpiredException`) would make error handling explicit and prevent accidentally swallowing unrelated errors.

**d. `parseRawMeal` is a pure function that mutates its output.**
Despite having no `async` I/O, `parseRawMeal` takes a `String` and modifies the growable lists inside a `WeekMeal.empty()`. It is not purely functional — it has hidden mutation. This violates the principle of least surprise for a function named `parse*`.

---

## 7. Cache Layer (`data.dart`)

### Issues

**a. Cache invalidation logic has a subtle off-by-one.**
`_getKstWeekNumber` computes `(diff.inDays / 7).toInt() + 1`. The `toInt()` floor on a floating-point division, combined with the UTC-to-KST shift, can produce a different week number for the same moment depending on DST or sub-day precision. Using `DateTime`'s ISO 8601 week number (`(date.difference(jan4).inDays / 7).floor() + 1`) would be more standard.

**b. Cache strategy is coarser than necessary.**
The cache is valid for an entire ISO week. Menu data could change day-by-day. The `downloadedMeal` future always fetches fresh data after cache is loaded, so this is partially mitigated, but the cache validity window is semantically broader than warranted.

**c. `data.dart` mixes I/O with business logic.**
`fetchAndCacheMealData()` performs three things: HTTP fetch, file write, and parse. `getCachedMealData()` performs file timestamp read, week number calculation, file read, and parse. These could be decomposed into smaller functions with single responsibilities.

---

## 8. UI Architecture

### Issues

**a. Direct coupling between UI and data layers.**
`home_page.dart` imports `api_v2.dart` and `data.dart` directly. A repository or service object would decouple the page from the data source, making the data layer independently testable and the page's dependencies explicit.

**b. `home_drawer.dart` accesses `SharedPreferences` directly.**
The drawer widget reads from `SharedPreferences` to retrieve the cached announcement text. This is business logic (persistence access) inside a UI widget. The announcement content should be passed in as state or loaded by a controller/model.

**c. `initState` performs async work without lifecycle guards.**
`_HomePageState.initState` fires two unawaited futures:
- `fetchRawAnnouncement().then(...)` — calls `showDialog(context: context, ...)` inside the callback. If the widget is disposed before the future resolves, this will attempt to use a stale `context`. The existing `mounted` check is absent here (unlike the button handler which has it).
- `rootBundle.loadString(...).then(...)` — calls `LicenseRegistry.addLicense(...)`, which is a global side effect that accumulates across hot reloads.

**d. Cafeteria identity check uses reference equality.**
In `week_meal_view.dart`, the cafeteria type is determined by:

```dart
if (meals == nowMeal.dormitory) { ... }
else if (meals == nowMeal.student) { ... }
else if (meals == nowMeal.faculty) { ... }
```

This compares `List<Meal>` references. It works only because the same list objects from `CafeteriaMeal` are iterated directly. If the code is ever refactored to copy or transform these lists, the identity check will silently fail and all cafeteria labels will be empty. The `Cafeteria` enum already exists and should be used to explicitly track which category a meal list belongs to.

**e. Meal card title construction is in the wrong layer.**
The logic for composing a cafeteria card title (e.g., "기숙사 식당 한식") lives in `WeekMealTabBarView`, which is a layout widget. Title construction is a domain concern and belongs closer to the data model or a presenter layer.

---

## 9. Custom Scroll System (`nested_page_scroll.dart`)

The scroll system is the most complex part of the codebase and is well-commented. The following are minor observations:

**a. `NestedPageScrollControllerGroup` extends `ChangeNotifier` without using it.**
The class extends `ChangeNotifier` but never calls `notifyListeners()` from its own public methods. The individual `NestedPageScrollController` instances call it (as they are also `ChangeNotifier` via `ScrollController`). If the group is not itself listened to, extending `ChangeNotifier` adds confusion.

**b. `prevPage` is initialized to `0` and never reset.**
`_NestedPageScrollViewState.prevPage` is set to `0.0` at field initialization and updated in `onVerticalDragStart`. Between drag sessions it retains the value from the last drag, not the actual current page position. If the user taps a tab to jump pages and then drags, `prevPage` may lag behind `currentPage`. The `middlePage` crossover calculation in `onVerticalDragUpdate` depends on this value for transition timing.

**c. `_isAnimatingPage` is mutated without `setState`.**
This is intentional (avoiding a rebuild), but it means the field is invisible to Flutter's rebuild cycle. A comment noting this intentional omission would aid future maintainers.

---

## 10. Summary Table

| Area | Severity | Issue |
|------|----------|-------|
| Theme | Medium | Non-idiomatic: should use `themeMode` + `darkTheme` instead of rebuilding `MaterialApp` |
| Theme | Low | `ColorScheme` surface overrides hardcoded per-build |
| i18n | High | Language detection permanently disabled (`true` replaces real condition) |
| i18n | Medium | Manual `Language` prop-drilling instead of `Localizations` |
| i18n | Medium | Hand-rolled date formatting instead of `intl` |
| i18n | Low | `string.dart` mixes string constants with formatting logic |
| State | Low | `HomePageModel` is ambiguously mutable; not a ChangeNotifier, not immutable |
| State | Low | `_isMealOfDayButtonTransition` is an ad-hoc boolean; could be an enum |
| State | Medium | Side effects (`PlatformDispatcher` callbacks) inside Provider `create:` |
| Data model | Low | Named fields + manual switch could be list-indexed by enum |
| Data model | Medium | Two-phase mutable construction via `empty()` + append pattern |
| Data model | Low | Subclass-as-type-tag (`KoreanMeal`/`HalalMeal`) |
| Data model | Low | `nextMealOfDay`/`nextDayOfWeek` should be extension methods |
| API | Medium | API keys in Korean string literals (fragile parsing) |
| API | Medium | Module-level HTTP client (untestable without DI) |
| API | Low | Untyped `Exception` for all errors |
| Cache | Low | Week-number calculation may have precision edge cases |
| Cache | Low | `data.dart` violates single responsibility |
| UI | Medium | `home_page.dart` directly imports `api_v2` / `data` (no repository layer) |
| UI | Medium | `home_drawer.dart` accesses `SharedPreferences` directly |
| UI | Medium | `initState` async futures lack `mounted` check (announcement path) |
| UI | Medium | Cafeteria identity check uses fragile reference equality |
| UI | Low | Card title construction belongs in domain layer, not layout widget |
| Scroll | Low | `NestedPageScrollControllerGroup` extends `ChangeNotifier` without notifying |
| Scroll | Low | `prevPage` not reset between drag sessions |

**Severity key:**
`High` — currently broken or misleading
`Medium` — works but deviates from Flutter conventions or will cause pain on future changes
`Low` — minor code quality, discoverability, or maintainability concern

---

## 11. Performance Optimization

This section identifies concrete, low-risk performance improvements that do not require structural rewrites. Each item is self-contained.

---

### 11-A. `AnimatedDateTitle` — string formatting on every animation frame

**File:** `lib/pages/home/home_app_bar.dart`

`AnimatedBuilder` fires its builder callback at ~60 fps during every tab swipe. The builder calls `string.getLocalizedDate(theDay.month, theDay.day, language)` — a switch statement plus string concatenation — on every single frame, even though the displayed text only changes once per swipe (when `animation.value.round()` crosses an integer boundary).

The week's seven date strings are fully determined at the moment `mondayOfWeek` and `language` are known (i.e., at widget construction), so they can be pre-computed once as a `List<String>`:

```dart
// Build once, outside AnimatedBuilder:
final dateLabels = List.generate(7, (i) {
  final day = mondayOfWeek.add(Duration(days: i));
  return string.getLocalizedDate(day.month, day.day, language);
});

// Inside AnimatedBuilder — only an integer index lookup:
return Text(dateLabels[displayIndex], ...);
```

Because `AnimatedDateTitle` currently is a `StatelessWidget`, moving to this pattern requires converting it to `StatefulWidget` (or pre-computing in the parent and passing the list in), but the change is minimal. The gain is eliminating `DateTime` arithmetic and string formatting from the 60 fps hot path entirely.

---

### 11-B. Unnecessary `setState` after meal-of-day button animation

**File:** `lib/pages/home/home_page.dart`, button handler in `build`

The button handler calls `setState` twice: once to update `_model.mealOfDay` and set the guard flag, and again after the animation completes to clear the flag:

```dart
// Second setState — only clears the guard flag
setState(() {
  _isMealOfDayButtonTransition = false;
});
```

`_isMealOfDayButtonTransition` is **not read in the `build` method** — it is only read inside the `onPageChanged` closure, which captures `this` (the state object) and reads the field value at call time rather than at build time. Therefore the second `setState` triggers a full rebuild of `_HomePageState.build` (including `Consumer`, AppBar, `dayOfMealLabel` switch, etc.) for no rendered change. The flag can be reset without `setState`:

```dart
// After animation completes, no rebuild needed:
_isMealOfDayButtonTransition = false;
```

The `mounted` guard around it must be kept. The first `setState` (which updates `_model.mealOfDay` for the button label) remains necessary.

---

### 11-C. `RepaintBoundary` around page content during meal-of-day transitions

**File:** `lib/pages/home/nested_page_scroll.dart`

During `animateToPageFromScroll` or `animateToPage`, the `PageView` animates between three pages (breakfast / lunch / dinner). Each page's content — a grid of `MealCard` widgets — is static and does not change during the animation. Without a `RepaintBoundary`, Flutter may re-rasterize the meal card content on every animation frame.

Wrapping the `SingleChildScrollView` content (or the `ConstrainedBox` child passed to it) in a `RepaintBoundary` lets the rasterizer cache the rendered layer and composite it without re-drawing during the page slide:

```dart
// In NestedPageScrollView's PageView.builder → itemBuilder:
child: RepaintBoundary(
  child: widget.builder(context, pageIndex),
)
```

This applies to both the touch-drag page transition and the pointer-scroll `animateToPageFromScroll` path, and costs only a single additional compositing layer per page (3 total).

---

### 11-D. `Consumer<BapUModel>` rebuilds on unrelated field changes

**File:** `lib/pages/home/home_page.dart`, `lib/main.dart`

`BapUModel` holds two unrelated fields: `language` and `themeBrightness`. `notifyListeners()` is coarse-grained, so every `Consumer<BapUModel>` rebuilds when **either** field changes.

Concretely:
- The `Consumer<BapUModel>` in `MyApp.build` rebuilds `MaterialApp` on language change, even though language does not affect `ThemeData`.
- The `Consumer<BapUModel>` wrapping `WeekMealTabBarView` in `home_page.dart` rebuilds the entire card grid on brightness change, even though `WeekMealTabBarView` only uses `language` from the model (theming flows through `Theme.of(context)` automatically).

Provider's `Selector` widget allows subscribing to a derived value and skipping rebuilds when only unrelated fields change:

```dart
// Only rebuilds when language changes, not when brightness changes:
Selector<BapUModel, Language>(
  selector: (_, model) => model.language,
  builder: (context, language, child) => WeekMealTabBarView(
    language: language, ...
  ),
)
```

The most impactful site is `MyApp.build`, where `MaterialApp` reconstruction on language change could be avoided with a split model (see §2c, §4c). Without splitting the model, `Selector` at each consumer site is the minimal change.

---

### 11-E. `MealCard` and `DayOfWeekTabBar` — HSL conversion per build

**Files:** `lib/pages/home/meal_card.dart`, `lib/pages/home/home_app_bar.dart`

Both widgets call `HSLColor.fromColor(...)` in `build`:

```dart
// MealCard.build — runs once per card per build
final primaryHsl = HSLColor.fromColor(theme.colorScheme.primaryContainer);

// DayOfWeekTabBar.build
final unselectedLabelColor = HSLColor.fromColor(colorScheme.onSurface)
    .withSaturation(0).withLightness(...).toColor();
```

These values change only when the theme changes (a rare, user-initiated event). A `ThemeExtension` that pre-computes and caches these derived colors would eliminate the conversions from the build path entirely. This is a low-risk, additive change:

```dart
// Define once, attached to ThemeData:
class BapUColors extends ThemeExtension<BapUColors> {
  final Color cardHeaderBackground;
  final Color cardHeaderText;
  final Color tabUnselectedLabel;
  ...
}
```

The impact is small (a few HSL operations per build), but it is the idiomatic Flutter approach for theme-derived colors that are expensive to recompute.

---

### Performance Summary

| # | Location | Impact | Risk | Status |
|---|----------|--------|------|--------|
| 11-A | `AnimatedDateTitle` — 60 fps string format | **High** (hot path) | Low | ✅ Applied |
| 11-B | `setState` after button animation | Medium | **Very low** | ✅ Applied |
| 11-C | `RepaintBoundary` on page content | Medium (animation smoothness) | Low | ⚠️ Reverted — causes first-render dim flash on page transitions |
| 11-D | `Selector` instead of `Consumer<BapUModel>` | Medium | Low–Medium | Pending |
| 11-E | HSL cache via `ThemeExtension` | Low | Low | Pending |
