# 아키텍처

밥먹어U(`meal_client`)의 코드 구조와 핵심 설계 결정을 정리한 문서입니다. AI 에이전트용 요약은 루트의 [AGENTS.md](../AGENTS.md)를 참고하세요.

## High-level System Diagram

```
┌─────────────────────────────────────────────────────────┐
│  UI 레이어                                               │
│                                                         │
│  BapUApp ──watch themeMode──► HomePage                  │
│     │                           │                       │
│     │ (ChangeNotifierProvider)  ├── AppBar              │
│     ▼                           ├── Drawer ──► Settings │
│  AppSettings ◄──read/write──────┘   │                   │
│  (ChangeNotifier)                   ▼                   │
│                              WeekMealView               │
│  HomePageModel  ◄── owned        └── MealCard × 3       │
│  ValueNotifier  ◄── owned                               │
└─────────────┬───────────────────────────────────────────┘
              │ FutureBuilder (식단 캐시 → /v2/menu) + shared AppInfo future
┌─────────────▼───────────────────────────────────────────┐
│  상태 / 도메인                                           │
│                                                         │
│  domain/meal.dart  ──  도메인 타입 (WeekMeal / …)        │
│  core/constants.dart  ──  ApiConstants / MealTimeConfig │
│                           / StorageKeys                 │
└─────────────┬───────────────────────────────────────────┘
              │
┌─────────────▼───────────────────────────────────────────┐
│  데이터 / 인프라                                         │
│                                                         │
│  features/meal/meal_data_source  ──  캐시 정책 + 식단 HTTP │
│    ├── core/network/http_client  ──  싱글톤 클라이언트   │
│    │           └── core/network/platform_http_client    │
│    │                 └── iOS/Android/Web 분기           │
│    └── core/widget_shared_storage                       │
│          └── meal.json / info.json 공유 캐시            │
│                                                         │
│  features/info/app_info  ──  /v2/info 모델              │
│  features/info/info_refresh_service                     │
│    └── /v2/info HTTP fetch + info.json raw cache write  │
│  features/info/announcement_state                        │
│    └── 공지 저장값 비교 + 표시 여부 판단                 │
└─────────────┬───────────────────────────────────────────┘
              │ refreshBackgroundMealAndInfoCaches() / keyword check
┌─────────────▼───────────────────────────────────────────┐
│  백그라운드 (Workmanager, 단일 callbackDispatcher)        │
│                                                         │
│  features/notification/meal_notification_worker         │
│    ├── bapu_meal_refresh → MealCache/InfoCache 갱신     │
│    └── meal_keyword_check_* → 키워드 매칭 → 로컬 알림    │
└─────────────────────────────────────────────────────────┘
```

## 레이어 개요

명시적인 경계(저장소 패턴 등)는 두지 않고, UI가 데이터 레이어를 직접 import 하는 단순한 3계층 구조입니다.

```
UI 레이어        → lib/features/home/ (home_page, home_app_bar, week_meal_view,
                                       meal_card, nested_page_scroll, home_drawer)
                  lib/features/settings/ (settings_page, allergy_selection_page)
상태 / 도메인    → lib/features/home/model.dart (HomePageModel),
                  lib/domain/meal.dart (도메인 타입),
                  lib/core/constants.dart,
                  lib/features/settings/ (AppSettings + 값 객체)
i18n             → lib/l10n/ (app_ko.arb, app_en.arb, 자동 생성된 AppLocalizations)
데이터 / 인프라  → lib/features/info/ (app_info.dart, info_cache.dart, info_refresh_service.dart,
                                      info_data_source.dart, announcement_state.dart),
                  lib/features/meal/ (meal_data_source.dart, meal_cache.dart,
                                      meal_refresh_service.dart, meal_background_refresh*.dart),
                  lib/features/notification/ (meal_alert_period.dart, notification_scheduler.dart,
                                              notification_service.dart, meal_notification_worker.dart),
                  lib/core/widget_shared_storage*.dart, lib/core/network/
```

## 핵심 컴포넌트

| 컴포넌트 | 파일 | 책임 | 상태 접근 |
|---|---|---|---|
| `BapUApp` | `main.dart` | MaterialApp 구성, 테마 적용 | `AppSettings` watch (themeMode) |
| `HomePage` | `features/home/home_page.dart` | 데이터 로딩, 공지 확인, Scaffold 조합 | `HomePageModel`, `ValueNotifier<MealOfDay>` 소유 |
| `HomeAppBar` | `features/home/home_app_bar.dart` | AppBar 구성 — 날짜, 요일 탭, 끼니 전환 버튼 | `ValueNotifier<MealOfDay>` 구독 (버튼만) |
| `WeekMealTabBarView` | `features/home/week_meal_view.dart` | 요일 탭뷰 + 반응형 카드 테이블, 식단 카드 운영시간 연결 | `Future<AppInfo>` read |
| `NestedPageScrollView` | `features/home/nested_page_scroll.dart` | 끼니 간 수평 PageView + 카드 내 수직 스크롤 통합 | — |
| `MealCard` | `features/home/meal_card.dart` | 식당별 메뉴 카드 표시, 운영시간/칼로리 표시, 공유 | — |
| `HomePageDrawer` | `features/home/home_drawer.dart` | 사이드바 — 공지/운영시간 다이얼로그, 설정 진입점 | `Future<AppInfo>` read |
| `SettingsPage` | `features/settings/settings_page.dart` | 설정 화면 (테마/알레르기/알림/위젯 섹션) | `AppSettings` read/watch |
| `AllergySelectionPage` | `features/settings/allergy_selection_page.dart` | 19개 알레르겐 체크리스트 | `AppSettings` read/write |
| `AppSettings` | `features/settings/app_settings.dart` | 앱 전역 설정 상태 소유 + SharedPreferences 영속화 | ChangeNotifier Provider 루트 배치 |

### 위젯 트리 (런타임)

```
BapUApp
└─ MaterialApp (themeMode ← AppSettings)
   └─ HomePage (StatefulWidget)
      ├─ AppBar
      │   ├─ AnimatedDateTitle
      │   ├─ ValueListenableBuilder<MealOfDay>
      │   │   └─ MealOfDaySwitchButton
      │   └─ DayOfWeekTabBar
      ├─ Drawer → HomePageDrawer
      │             ├─ 공지사항 다이얼로그
      │             ├─ 운영시간 다이얼로그
      │             └─ [Settings 진입] → SettingsPage
      │                                    └─ AllergySelectionPage
      └─ Body (FutureBuilder: cachedMeal)
          └─ FutureBuilder: downloadedMeal
              └─ WeekMealTabBarView (TabBarView × 7일)
                  └─ NestedPageScrollView (PageView × 3끼니)
                      └─ MealCard × 3 (기숙사 / 학생 / 교직원)
```

## 상태 관리

두 종류의 상태가 분리되어 있습니다.

- **`HomePageModel`** (`lib/features/home/model.dart`)
  화면 로컬 선택 상태(현재 끼니, 요일 등). 평범한 가변 객체이며 `_HomePageState`가 소유합니다. 끼니 버튼 상태는 `ValueNotifier<MealOfDay>`로 분리해 끼니 전환 시 `MealOfDaySwitchButton` 중심으로 리빌드 범위를 좁혔습니다.

- **`AppSettings extends ChangeNotifier`** (`lib/features/settings/app_settings.dart`)
  앱 전역 사용자 설정의 단일 소유자입니다. 루트에 `ChangeNotifierProvider<AppSettings>`가 한 번만 배치되며, `context.watch<AppSettings>()` 또는 `context.read<AppSettings>()`로 접근합니다. `SharedPreferences`에 즉시 영속화하고, 변경 시 `notifyListeners()`를 호출합니다.

  서브 설정은 모두 불변 값 객체입니다.
  - `AllergySettings` (`lib/features/settings/allergy_settings.dart`) — 켜진 알레르겐 ID 집합 (1–19)
  - `NotificationSettings` (`lib/features/settings/notification_settings.dart`) — 알림 on/off, 키워드, 시각, 대상 식당
  - `WidgetSettings` (`lib/features/settings/widget_settings.dart`) — 위젯에 표시할 식당과 끼니
  - `ThemeMode` — Flutter 표준 enum 그대로 사용

  주의: 알레르기는 **저장만 되는 플레이스홀더**입니다(실제 알레르겐 하이라이트는 후속 작업). 위젯도 이 브랜치에는 네이티브 구현이 없는 플레이스홀더입니다. 반면 알림은 `features/notification/`을 통해 실제로 동작합니다 — `AppSettings`가 on/off·시간대별 시각 변경 시 `notification_scheduler.dart`를 호출해 Workmanager 태스크를 직접 등록/취소합니다. 테마 전환과 알림은 즉시 반영되는 실기능입니다.

`BapUModel` 플레이스홀더는 더 이상 존재하지 않습니다(`d1da738`에서 삭제).

## 테마

Flutter 표준 방식을 사용합니다.

```dart
MaterialApp(
  themeMode: themeMode,                  // AppSettings에서 watch
  theme:     _buildTheme(Brightness.light),
  darkTheme: _buildTheme(Brightness.dark),
  ...
)
```

`_buildTheme(Brightness)`은 `lib/main.dart`에 있으며 `ColorScheme.fromSeed`로 라이트/다크 테마를 각각 생성합니다. 시드 컬러는 `mainColor = #00CD80`. 시스템 밝기 변경은 프레임워크가 자동으로 처리합니다.

## 다국어

`flutter_localizations` + `intl` 기반.

- 번역 리소스는 `lib/l10n/app_ko.arb` (한국어, 기본), `lib/l10n/app_en.arb` (영어).
- `lib/l10n/app_localizations*.dart`는 `flutter gen-l10n`으로 자동 생성됩니다 — **직접 편집 금지**, 항상 ARB 파일을 수정한 뒤 재생성합니다.
- 사용 시: `AppLocalizations.of(context)!.someKey`.

## 상수

매직 문자열·숫자는 모두 `lib/core/constants.dart`에 모았습니다.

- `ApiConstants` — 백엔드 엔드포인트 URL
- `MealTimeConfig` — 끼니 시간 경계 및 `determineMealOfDay()` 로직
- `StorageKeys` — `SharedPreferences` 키와 캐시 파일 이름
  - raw 공유 캐시: `mealCacheFile`(`meal.json`), `infoCacheFile`(`info.json`)
  - 공지 비교: `announcementKey`
  - 설정: `settings_*` prefix로 통일 (`allergenIds`, `notificationEnabled`, `notificationKeywords`, `notificationPeriodTimePrefix`, `notificationPeriodRememberedPrefix`, `notificationCafeterias`, `widgetCafeteria`, `widgetMealOfDay`, `themeMode`)

## 데이터 흐름

### 식단 데이터 로딩 흐름

```
앱 시작
  │
  ├─► cachedMeal ──────────────────────────────────────────────►┐
  │     같은 KST 주차?                                          │
  │       Yes → WeekMeal 반환 → UI에 즉시 표시                  │
  │       No  → Exception                                       │
  │                                                             │
  └─► downloadedMeal = cachedMeal.then(fetch, onError: fetch)   │
        네트워크 성공 → WeekMeal 반환 → UI 갱신 ────────────────►┤
        네트워크 실패 → Exception                                │
                                                                 ▼
                                                          FutureBuilder
                                                          ├ 캐시 or 네트워크 성공 → 데이터 표시
                                                          ├ 하나만 성공 중 → 스피너
                                                          └ 둘 다 실패 → 에러 텍스트
```

### FutureBuilder 체인 구조

`_HomePageState.initState()`에서 두 Future를 동시에 시작합니다.

```dart
cachedMeal = getCachedMealData();
downloadedMeal = cachedMeal.then(
  (_) => fetchAndCacheMealData(),   // 캐시 성공 → 그래도 fetch
  onError: (_) => fetchAndCacheMealData(), // 캐시 실패 → fetch
);
```

| 상태 | UI 동작 |
|---|---|
| 캐시 로딩 중 | 스피너 |
| 캐시 성공, 네트워크 로딩 중 | 캐시 데이터 표시 (최신 아닐 수 있음) |
| 네트워크 성공 | 최신 데이터로 자동 갱신 |
| 캐시 실패, 네트워크 로딩 중 | 스피너 |
| 캐시 + 네트워크 모두 실패 | `l10n.cannotLoadMeal` 텍스트 |
| 네트워크만 실패 | 캐시 데이터 유지 (에러 숨김) |

### 앱 정보(`/v2/info`) 로딩 흐름

`_HomePageState.initState()`에서 식단 Future와 별도로 앱 정보 Future를 한 번 생성합니다.

```dart
late final Future<AppInfo> appInfo;

@override
void initState() {
  ...
  appInfo = fetchAppInfo();
  _checkAnnouncement();
}
```

이 `Future<AppInfo>`는 세 곳에서 공유됩니다.

| 소비자 | 사용 목적 |
|---|---|
| `_checkAnnouncement()` | `AppInfo.announcement`를 기존 저장 공지와 비교하고 새 공지이면 자동 팝업 |
| `HomePageDrawer` | 공지사항 수동 확인, 운영시간 다이얼로그 표시 |
| `WeekMealTabBarView` | 선택한 날짜/끼니/식당의 운영시간을 식단 카드에 전달 |

`fetchAppInfo()`는 내부적으로 `InfoRefreshService.refreshInfo()`를 호출합니다. 이 서비스는 `/v2/info` raw JSON을 먼저 파싱/검증한 뒤, 공유 위젯 캐시 위치에 `info.json`으로 저장하고 `AppInfo`를 반환합니다. 앱 UI는 현재 세션의 `Future<AppInfo>`를 공유합니다. 이 브랜치에는 아직 `info.json`을 cache-only로 읽는 네이티브 위젯이 없습니다(`develop-widget`에 구현되어 있으며 병합 시 함께 들어옵니다).

공지사항과 운영시간 다이얼로그는 `SelectionArea`로 감싸져 있어 제목과 본문 텍스트를 선택/복사할 수 있습니다.

### 공유 캐시와 무효화

`meal.json`과 `info.json`은 앱과 background refresh가 공유하는 raw JSON 캐시입니다(향후 `develop-widget`의 native 위젯도 같은 파일을 읽도록 준비된 공유 경계입니다). 이 두 파일만 `core/widget_shared_storage.dart`를 통해 저장 위치를 고릅니다.

- Android: `getApplicationSupportDirectory()`와 native `context.filesDir`가 같은 앱 내부 디렉터리를 가리킵니다.
- iOS: native bridge가 반환하는 App Group 컨테이너를 사용합니다. Dart에는 App Group ID를 하드코딩하지 않습니다.
- Web: 공유 파일 캐시가 없으므로 stub이 예외/no-op로 동작합니다.

`MealCache.hasFreshMealCache()`는 파일 마지막 수정 시각과 현재 시각을 모두 KST 기준 단조 week id로 변환해 비교합니다. 기준점은 1970-01-05 월요일 00:00 UTC이며, ISO week-number나 연도 경계 영향을 받지 않습니다. 주 ID가 다르면 stale로 보고 Dart foreground/background fetch가 `/v2/menu`를 다시 받아 `meal.json`을 갱신합니다.

`info.json`은 별도 freshness 판정 없이 `/v2/info` refresh 성공 시마다 raw 응답으로 갱신됩니다.

### 백그라운드 새로고침과 키워드 알림

`main.dart`는 native 플랫폼에서 Workmanager를 초기화합니다. 등록 task 이름은 `bapu_meal_refresh`이고, 주기는 1시간입니다. Workmanager는 앱당 콜백 dispatcher를 하나만 등록할 수 있으므로, `features/notification/meal_notification_worker.dart`의 `callbackDispatcher()`가 식단/공지 캐시 새로고침과 키워드 알림 검사 태스크를 모두 처리합니다. `features/meal/meal_background_refresh*`는 주기 task 이름·등록만 담당하고, 두 번째 dispatcher를 추가하지 않습니다.

- `bapu_meal_refresh` 태스크: `refreshBackgroundMealAndInfoCaches()`가 `MealRefreshService`와 `InfoRefreshService`를 각각 호출해 `meal.json`/`info.json`을 갱신합니다. `meal.json` cache write 실패는 task failure로 돌리지만, `/v2/info` fetch/parse 실패는 (raw cache write 자체가 실패한 경우를 제외하면) 키워드 알림 검사를 막지 않습니다.
- `meal_keyword_check_<period>` 태스크: `features/notification/notification_scheduler.dart`가 시간대(`MealAlertPeriod`: 아침/점심/저녁/밤)별로 등록한 one-off task입니다. 실행되면 SharedPreferences에서 알림 설정을 직접 읽고, `MealRefreshService.getFreshOrRefreshMealData()`로 얻은 `WeekMeal`에서 키워드를 매칭해 `features/notification/notification_service.dart`로 로컬 알림을 표시한 뒤, 같은 시각으로 다음날 태스크를 재등록합니다.
- `AppSettings`는 알림 on/off·시간대별 시각 변경 시 `notification_scheduler.dart`를 직접 호출해 Workmanager 태스크를 등록/취소합니다. 앱 시작 시에도 활성화된 시간대 알림을 한 번 더 재스케줄해, 백그라운드 워커의 다음 회차 등록 실패에 대비합니다.
- 디버그 빌드에는 `testMealKeywordCheck()`로 백그라운드 로직을 메인 isolate에서 즉시 실행해보는 테스트 경로가 있습니다.

Android는 WorkManager `NetworkType.connected` 제약을 사용합니다. iOS BGTaskScheduler는 동일한 네트워크 제약을 보장하지 않으며, 실행 시점도 시스템 정책에 좌우됩니다.

Android 네이티브 홈 화면 위젯은 이 브랜치에는 없습니다(별도 `develop-widget` 브랜치에서 구현 중). 병합되면 그 native 위젯이 같은 `meal.json`/`info.json` cache-only 계약을 그대로 재사용할 수 있어야 합니다.

## 플랫폼 분기

조건부 export(`dart.library.js_interop` 기반 컴파일 타임 분기)로 플랫폼별 구현을 선택합니다.

```dart
// core/widget_shared_storage.dart
export 'widget_shared_storage_io.dart'
    if (dart.library.js_interop) 'widget_shared_storage_web.dart';
```

| 추상 모듈 | 네이티브 (`*_io.dart`) | 웹 (`*_web.dart`) |
|---|---|---|
| `lib/core/widget_shared_storage.dart` | Android/desktop: app support storage, iOS: App Group container | 공유 위젯 캐시 없음 |
| `lib/core/network/platform_http_client.dart` | iOS: `cupertino_http` / Android: `cronet_http` | 기본 `http` 패키지 |

`core/network/http_client.dart`는 전역 HTTP 클라이언트 싱글톤(`appHttpClient`)을 보유합니다. 앱 시작 시 `createPlatformHttpClient()`로 한 번 생성되고, 앱 종료 시까지 재사용됩니다. 타임아웃은 10초.

## 도메인 모델

```
WeekMeal
 └─ DayMeal × 7  (DayOfWeek enum 인덱스)
     └─ CafeteriaMeal × 3  (Cafeteria enum 인덱스)
         └─ List<Meal>  (KoreanMeal | HalalMeal)
```

- 식당: 기숙사식당 / 학생식당 / 교직원식당 (`Cafeteria` enum)
- 끼니: 아침 / 점심 / 저녁 (`MealOfDay` enum)
- `Meal`은 `MealMenuItem(ko, en?)` 목록과 선택적 `kcal`을 갖습니다. UI는 `localizedMenu(languageCode)`로 현재 언어에 맞는 메뉴명을 얻으며, 영어 메뉴명이 없으면 한국어로 fallback합니다.
- `CafeteriaMeal.empty()`이 growable 리스트를 만들고, `parseRawMeal`이 그 리스트를 변이시켜 채우는 **2단계 초기화 패턴**입니다. API 응답을 순서대로 파싱하면서 식당별 리스트에 추가하는 방식이기 때문에, 불변 객체로 한 번에 생성하려면 전체를 먼저 분류한 뒤 생성해야 하는 불필요한 중간 버퍼가 생깁니다.
- `/v2/menu` 응답의 식당 키(`DORMITORY`, `STUDENT`, `FACULTY`), 요일 키(`MON`..`SUN`), 끼니 키(`BREAKFAST`, `LUNCH`, `DINNER`)는 각 도메인 enum으로 매핑합니다.
- 현재 UI는 `sectionType == REGULAR` 섹션만 표시합니다. `SALAD`, `CONVENIENCE`, `SPECIAL`, `sectionTitle`, section-level calorie/allergen 표시는 후속 UI 설계 범위입니다.
- `parseRawMeal`은 본래 `api_v2.dart`에 있었으나 도메인 책임을 명확히 하기 위해 `meal.dart`로 이동했습니다 (`0d331a2`).

## 앱 정보 모델

`lib/features/info/app_info.dart`는 `/v2/info` 응답을 모델링합니다.

```
AppInfo
 ├─ AppAnnouncement? announcement
 │   ├─ LocalizedText? title
 │   ├─ LocalizedText content
 │   └─ bool showAnnouncementEveryTime
 └─ OperatingHours operatingHours
     ├─ OperatingHoursPeriod weekday
     └─ OperatingHoursPeriod weekend
         └─ Cafeteria → MealOfDay → OperatingTimeRange
```

- `announcement` 자체가 `null`일 수 있습니다.
- `announcement.title`도 `null`일 수 있으며, UI는 기본 i18n 라벨(`공지사항` / `Announcement`)로 fallback합니다.
- `announcement.content`는 `LocalizedText`로 한국어/영어 값을 갖습니다.
- `features/info/announcement_state.dart`는 저장된 공지 JSON과 새 공지의 `contentFingerprint`를 비교합니다. 기존 버전에서 저장된 raw string 공지도 `fromStoredString()`으로 읽을 수 있습니다.
- `OperatingHours.forDate(DateTime kstDate)`는 KST 날짜 기준으로 평일/주말 운영시간을 고릅니다.
- `OperatingTimeRange.contains(DateTime time)`는 현재 시간이 해당 운영시간 안인지 판정합니다.

## API 엔드포인트

`lib/core/constants.dart`의 `ApiConstants`에 엔드포인트를 모았습니다.

| 엔드포인트 | 용도 | 현재 소비자 |
|---|---|---|
| `mealEndpoint` (`/v2/menu`) | 현재 주 식단 데이터 | `features/meal/meal_data_source.dart` |
| `infoEndpoint` (`/v2/info`) | 공지사항 + 운영시간 | `features/info/info_data_source.dart` |
| `noticeEndpoint` (`/notice`) | 기존 공지 API 상수 | 현재 주요 흐름에서는 `/v2/info`의 `announcement` 사용 |

## 커스텀 스크롤 시스템

**해결하는 문제:** Flutter의 `PageView`(수평 스와이프)와 그 안에 중첩된 `ListView`(수직 스크롤) 사이에서 발생하는 제스처 충돌 — 수직에 가까운 스와이프가 내부 스크롤에 빼앗기거나, 수평 스와이프가 외부 PageView로 넘어가지 못하는 현상을 처리합니다.

`lib/features/home/nested_page_scroll.dart`는 끼니 간 가로 스와이프(PageView)와 카드 내부 세로 스크롤을 통합 처리하는 `NestedPageScrollController` / `NestedPageScrollView` / `NestedPageScrollControllerGroup`을 정의합니다. 코드베이스에서 가장 복잡한 부분이므로 수정 전 자세한 분석은 [`docs/features/nested_page_scroll.md`](features/nested_page_scroll.md)와 파일 내 주석을 참고하세요.

## 주요 의존성

| 패키지 | 용도 |
|---|---|
| `provider` | `AppSettings` ChangeNotifier를 위젯 트리에 공급 |
| `http` | HTTP 클라이언트 기반 인터페이스 |
| `cupertino_http` | iOS 네이티브 NSURLSession 기반 클라이언트 |
| `cronet_http` | Android Cronet 기반 클라이언트 (HTTP/3 지원) |
| `shared_preferences` | 설정 값 영속화 |
| `workmanager` | 식단/공지 캐시 백그라운드 새로고침 + 키워드 알림 스케줄링 |
| `flutter_local_notifications` | 키워드 매칭 시 로컬 알림 표시 |
| `app_settings` | 알림 권한 거부 시 OS 설정 화면으로 이동 |
| `flutter_svg` | 사이드바 로고(`bapu_logo.svg`) 렌더링 |
| `flutter_localizations` + `intl` | 한국어/영어 다국어 지원 |

## 디렉터리 구조

```
lib/
├── main.dart                              앱 진입점, ChangeNotifierProvider, MaterialApp
├── core/
│   ├── constants.dart                     ApiConstants, MealTimeConfig, StorageKeys
│   ├── widget_shared_storage.dart         조건부 export
│   ├── widget_shared_storage_io.dart      공유 raw cache 파일 저장소
│   ├── widget_shared_storage_web.dart     웹 stub
│   └── network/
│       ├── http_client.dart               전역 HTTP 싱글톤 + fetchRawString
│       ├── platform_http_client.dart      조건부 export
│       ├── platform_http_client_io.dart   Cupertino / Cronet 클라이언트
│       └── platform_http_client_web.dart  웹 클라이언트
├── domain/
│   └── meal.dart                          도메인 타입 + parseRawMeal
├── features/
│   ├── home/
│   │   ├── home_page.dart                 메인 화면, FutureBuilder 체인
│   │   ├── home_app_bar.dart              AppBar (끼니 스위치 / 요일 탭 / 날짜)
│   │   ├── home_drawer.dart               드로어, 공지/운영시간 다이얼로그, 설정 진입점
│   │   ├── meal_card.dart                 식당별 메뉴 카드, 운영시간/칼로리 표시
│   │   ├── model.dart                     HomePageModel
│   │   ├── nested_page_scroll.dart        중첩 스크롤 시스템
│   │   └── week_meal_view.dart            요일 탭뷰 + 반응형 카드 테이블
│   ├── info/
│   │   ├── app_info.dart                  /v2/info 모델 (공지 + 운영시간)
│   │   ├── info_cache.dart                info.json raw cache
│   │   ├── info_refresh_service.dart      /v2/info HTTP fetch + cache write
│   │   ├── info_data_source.dart          fetchAppInfo facade
│   │   └── announcement_state.dart        /v2/info 공지 비교·저장
│   ├── meal/
│   │   ├── meal_cache.dart                meal.json raw cache + freshness
│   │   ├── meal_refresh_service.dart      /v2/menu HTTP fetch + cache write
│   │   ├── meal_background_refresh.dart   조건부 export
│   │   ├── meal_background_refresh_io.dart bapu_meal_refresh 주기 task 등록
│   │   ├── meal_background_refresh_stub.dart
│   │   └── meal_data_source.dart          식단 loading facade
│   ├── notification/
│   │   ├── meal_alert_period.dart         시간대(아침/점심/저녁/밤) + 15분 슬롯 정의
│   │   ├── notification_scheduler.dart    시간대별 Workmanager one-off task 등록/취소
│   │   ├── notification_service.dart      flutter_local_notifications 채널/권한/표시
│   │   └── meal_notification_worker.dart  Workmanager callbackDispatcher (meal/info refresh + 키워드 검사)
│   └── settings/
│       ├── app_settings.dart              AppSettings ChangeNotifier
│       ├── allergy_selection_page.dart    19개 알레르겐 체크리스트
│       ├── allergy_settings.dart          AllergySettings 값 객체
│       ├── notification_settings.dart     NotificationSettings 값 객체
│       ├── settings_page.dart             설정 화면 (테마 / 알레르기 / 알림 / 위젯)
│       └── widget_settings.dart           WidgetSettings 값 객체
└── l10n/                                  ARB + 자동 생성된 AppLocalizations
```

## 테스트

- `test/domain_test.dart` — 도메인 모델 / `/v2/menu` 파싱 로직 단위 테스트
- `test/info_test.dart` — `/v2/info` 모델 파싱, 공지 저장/비교 로직 테스트
- `test/home_drawer_test.dart` — 드로어 운영시간 항목과 평일/주말 팝업 테스트
- `test/meal_card_test.dart` — 식단 카드 운영시간 표시 상태 테스트
- `test/week_meal_view_test.dart` — 선택 요일/끼니 운영시간 전달 테스트
- `test/settings_test.dart` — `AppSettings` 및 값 객체 단위 테스트
- `test/widget_test.dart` — 앱 렌더링 / 테마 스모크 테스트
- `test/features/info/info_refresh_service_test.dart` — `/v2/info` raw cache write 검증
- `test/features/meal/meal_cache_test.dart` — `meal.json` raw cache freshness 검증
- `test/features/meal/meal_refresh_service_test.dart` — `/v2/menu` refresh/cache write 검증
- `test/features/notification/meal_notification_worker_test.dart` — 백그라운드 캐시 새로고침/키워드 알림 워커 단위 테스트

미커버 영역: `nested_page_scroll.dart` 제스처 상호작용, 웹 플랫폼 전용 분기(`widget_shared_storage_web.dart`), 실제 Workmanager 트리거 e2e, 실기기 알림 전달/타이밍.

테스트 설명은 한국어로 작성합니다.

## 컨벤션

- 코드 주석: 한국어
- 커밋 메시지: 영어 (복잡한 경우 한국어 허용)
- 테스트 설명: 한국어
- AI 도구용 plan/spec: 영어
- l10n 키: 영어 / 값: 한국어·영어
- 폰트: Pretendard (`assets/fonts/`에 번들)
- 주 색상: `#00CD80` (`mainColor`, `lib/main.dart`)
