# AGENTS.md

This file provides guidance to LLM coding agents when working with code in this repository.

## Project

BapU (밥먹어U) — Flutter app for viewing UNIST cafeteria menus. Version 5.0.1+18, GPL-2.0, by HeXA-UNIST.
Backend API: `https://meal.hexa.pro/`

Targets: Android, iOS, Web. Dart SDK ^3.8.1.

## Build & Development Commands

```bash
# Run (debug)
flutter run

# Build
flutter build apk
flutter build ios
flutter build web

# Analyze (lint)
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Get dependencies
flutter pub get
```

Lint rules: `package:flutter_lints/flutter.yaml` (see `analysis_options.yaml`). `dead_code` is set to `info` severity.

## Architecture

Three layers, no explicit boundary (no repository pattern). UI imports data layer directly.

```
UI Layer          → pages/home/ (home_page, home_app_bar, week_meal_view, meal_card, nested_page_scroll), home_drawer
State/Domain      → model.dart (BapUModel via Provider ChangeNotifier), meal.dart (domain types), i18n.dart, string.dart
Data/Infra        → api_v2.dart (HTTP + JSON parse), data.dart (cache-first-then-network), storage*.dart, platform_http_client*.dart
```

### Key Architectural Decisions

- **State management**: Provider with `ChangeNotifier`. `BapUModel` holds global state (language + brightness). `HomePageModel` is a plain mutable class managed via `setState` in `_HomePageState`.
- **Theme**: Non-standard — uses `BapUModel.themeBrightness` to rebuild entire `MaterialApp` with new `ThemeData` on brightness change, instead of Flutter's `themeMode`/`darkTheme`. This is intentional (see ARCHITECTURE.md §2 for tradeoffs).
- **Language**: Supports Korean(Primary) and English. (flutter_localizations + intl)
- **Data flow**: `home_page.dart` uses FutureBuilder chain — loads cached data first (`getCachedMealData`), then fetches fresh data (`fetchAndCacheMealData`). Cache invalidation is week-number based.
- **Platform branching**: Conditional exports for storage (`storage.dart` → `storage_io.dart` / `storage_web.dart`) and HTTP client (`platform_http_client.dart` → `*_io.dart` / `*_web.dart`). iOS uses cupertino_http, Android uses cronet_http.
- **Custom scroll system**: `nested_page_scroll.dart` implements a complex nested PageView+ScrollView system for swiping between meals (breakfast/lunch/dinner) with inner content scrolling. This is the most complex part of the codebase — read its comments carefully before modifying.

### Domain Model

- Three cafeterias: Dormitory (기숙사), Student (학생), Faculty (교직원)
- `WeekMeal` → 7 `DayMeal` (named fields: mon–sun) → 3 `CafeteriaMeal` (breakfast/lunch/dinner) → lists of `Meal` subclasses (`KoreanMeal`, `HalalMeal`)
- Enum dispatch via `switch` on named fields (not list-indexed). Adding a cafeteria requires updating both the enum and all switch statements.
- `CafeteriaMeal.empty()` creates growable lists; `parseRawMeal` mutates them during construction (two-phase init pattern).

### API

- `parseRawMeal` switches on Korean string literals from the API (`"기숙사 식당"`, `"학생 식당"`, `"교직원 식당"`)
- Global HTTP client singleton in `api_v2.dart`

## Known TODOs

- Settings screen
- Home screen widget (note: cache uses `getApplicationSupportDirectory()`, inaccessible from widgets)
- Theme system migration to standard `themeMode`/`darkTheme`

## Conventions

- Comments and commit messages may be in Korean
- Write comments in Korean
- Test file has Korean test descriptions
- Font: Pretendard (bundled in assets)
- Primary color: `#00CD80`
