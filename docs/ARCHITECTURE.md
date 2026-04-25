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
              │ FutureBuilder (캐시 → 네트워크)
┌─────────────▼───────────────────────────────────────────┐
│  상태 / 도메인                                           │
│                                                         │
│  meal.dart  ──  도메인 타입 (WeekMeal / DayMeal / …)     │
│  constants.dart  ──  ApiConstants / MealTimeConfig /    │
│                      StorageKeys                        │
└─────────────┬───────────────────────────────────────────┘
              │
┌─────────────▼───────────────────────────────────────────┐
│  데이터 / 인프라                                         │
│                                                         │
│  data.dart  ──  캐시 정책 (KST week 기반 무효화)        │
│    ├── api_v2.dart  ──  HTTP 호출 + JSON 파싱           │
│    │     └── platform_http_client  ──  iOS/Android/Web  │
│    └── storage  ──  파일 캐시 (네이티브) / stub (웹)    │
│                                                         │
│  announcement_service.dart  ──  공지 확인               │
└─────────────────────────────────────────────────────────┘
```
    HPM -->|setState 없이| HP
    MOD_VN -->|ValueListenableBuilder| APPBAR
    MEAL --> DATA_F

    ARB --> AL
    AL --> HP
    AL --> SETTINGS
```

## 레이어 개요

명시적인 경계(저장소 패턴 등)는 두지 않고, UI가 데이터 레이어를 직접 import 하는 단순한 3계층 구조입니다.

```
UI 레이어        → lib/pages/home/, lib/pages/home_drawer.dart,
                  lib/pages/settings_page.dart, lib/pages/allergy_selection_page.dart
상태 / 도메인    → lib/model.dart (HomePageModel),
                  lib/meal.dart (도메인 타입),
                  lib/constants.dart,
                  lib/settings/ (AppSettings + 값 객체)
i18n             → lib/l10n/ (app_ko.arb, app_en.arb, 자동 생성된 AppLocalizations)
데이터 / 인프라  → lib/api_v2.dart, lib/announcement_service.dart,
                  lib/data.dart, lib/storage*.dart, lib/platform_http_client*.dart
```

## 핵심 컴포넌트

| 컴포넌트 | 파일 | 책임 | 상태 접근 |
|---|---|---|---|
| `BapUApp` | `main.dart` | MaterialApp 구성, 테마 적용 | `AppSettings` watch (themeMode) |
| `HomePage` | `pages/home/home_page.dart` | 데이터 로딩, 공지 확인, Scaffold 조합 | `HomePageModel`, `ValueNotifier<MealOfDay>` 소유 |
| `HomeAppBar` | `pages/home/home_app_bar.dart` | AppBar 구성 — 날짜, 요일 탭, 끼니 전환 버튼 | `ValueNotifier<MealOfDay>` 구독 (버튼만) |
| `WeekMealTabBarView` | `pages/home/week_meal_view.dart` | 요일 탭뷰 + 반응형 카드 테이블 | — |
| `NestedPageScrollView` | `pages/home/nested_page_scroll.dart` | 끼니 간 수평 PageView + 카드 내 수직 스크롤 통합 | — |
| `MealCard` | `pages/home/meal_card.dart` | 식당별 메뉴 카드 표시, 공유 | — |
| `HomePageDrawer` | `pages/home_drawer.dart` | 사이드바 — 공지, 운영 시간, 설정 진입점 | — |
| `SettingsPage` | `pages/settings_page.dart` | 설정 화면 (테마/알레르기/알림/위젯 섹션) | `AppSettings` read/watch |
| `AllergySelectionPage` | `pages/allergy_selection_page.dart` | 19개 알레르겐 체크리스트 | `AppSettings` read/write |
| `AppSettings` | `settings/app_settings.dart` | 앱 전역 설정 상태 소유 + SharedPreferences 영속화 | ChangeNotifier Provider 루트 배치 |

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

- **`HomePageModel`** (`lib/model.dart`)
  화면 로컬 선택 상태(현재 끼니, 요일 등). 평범한 가변 객체이며 `_HomePageState`에서 `setState`로 관리합니다. 끼니 전환 같은 일부 상태는 `ValueNotifier`로 분리해 리빌드 범위를 좁혔습니다.

- **`AppSettings extends ChangeNotifier`** (`lib/settings/app_settings.dart`)
  앱 전역 사용자 설정의 단일 소유자입니다. 루트에 `ChangeNotifierProvider<AppSettings>`가 한 번만 배치되며, `context.watch<AppSettings>()` 또는 `context.read<AppSettings>()`로 접근합니다. `SharedPreferences`에 즉시 영속화하고, 변경 시 `notifyListeners()`를 호출합니다.

  서브 설정은 모두 불변 값 객체입니다.
  - `AllergySettings` (`lib/settings/allergy_settings.dart`) — 켜진 알레르겐 ID 집합 (1–19)
  - `NotificationSettings` (`lib/settings/notification_settings.dart`) — 알림 on/off, 키워드, 시각, 대상 식당
  - `WidgetSettings` (`lib/settings/widget_settings.dart`) — 위젯에 표시할 식당과 끼니
  - `ThemeMode` — Flutter 표준 enum 그대로 사용

  주의: 알레르기 / 알림 / 위젯은 **저장만 되는 플레이스홀더**입니다. 실제 알레르겐 하이라이트, 푸시 스케줄링, 위젯 플랫폼 코드는 후속 작업입니다. 테마 전환만 즉시 반영되는 실기능입니다.

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

매직 문자열·숫자는 모두 `lib/constants.dart`에 모았습니다.

- `ApiConstants` — 백엔드 엔드포인트 URL
- `MealTimeConfig` — 끼니 시간 경계 및 `determineMealOfDay()` 로직
- `StorageKeys` — `SharedPreferences` 키와 캐시 파일 이름
  - 식단 캐시: `mealCacheFile`, 공지 비교: `announcementKey`
  - 설정: `settings_*` prefix로 통일 (`allergenIds`, `notificationEnabled`, `notificationKeyword`, `notificationTime`, `notificationCafeterias`, `widgetCafeteria`, `widgetMealOfDay`, `themeMode`)

## 데이터 흐름

### 데이터 로딩 흐름

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

### 캐시 무효화

`getCachedMealData()`는 캐시 파일의 마지막 수정 시각과 현재 시각을 모두 **KST(UTC+9) 기준 ISO week number**로 변환해 비교합니다. 주차가 다르면 `Exception("Outdated cache")`를 던지고 네트워크 fetch로 폴백합니다.

```dart
int _getKstWeekNumber(DateTime time) {
  final kst = time.toUtc().add(Duration(hours: 9));
  // ISO 주의 첫날(월요일)을 기준으로 경과 일수 계산
  ...
}
```

## 플랫폼 분기

조건부 export(`dart.library.js_interop` 기반 컴파일 타임 분기)로 플랫폼별 구현을 선택합니다.

```dart
// storage.dart
export 'storage_io.dart' if (dart.library.js_interop) 'storage_web.dart';
```

| 추상 모듈 | 네이티브 (`*_io.dart`) | 웹 (`*_web.dart`) |
|---|---|---|
| `lib/storage.dart` | `getApplicationSupportDirectory()` 기반 JSON 파일 캐시 | 파일 캐시 비활성, 매번 fetch |
| `lib/platform_http_client.dart` | iOS: `cupertino_http` / Android: `cronet_http` | 기본 `http` 패키지 |

`api_v2.dart`는 전역 HTTP 클라이언트 싱글톤(`_httpClient`)을 보유합니다. 앱 시작 시 `createPlatformHttpClient()`로 한 번 생성되고, 앱 종료 시까지 재사용됩니다. 타임아웃은 10초.

## 도메인 모델

```
WeekMeal
 └─ DayMeal × 7  (DayOfWeek enum 인덱스)
     └─ CafeteriaMeal × 3  (Cafeteria enum 인덱스)
         └─ List<Meal>  (KoreanMeal | HalalMeal)
```

- 식당: 기숙사식당 / 학생식당 / 교직원식당 (`Cafeteria` enum)
- 끼니: 아침 / 점심 / 저녁 (`MealOfDay` enum)
- `CafeteriaMeal.empty()`이 growable 리스트를 만들고, `parseRawMeal`이 그 리스트를 변이시켜 채우는 **2단계 초기화 패턴**입니다. API 응답을 순서대로 파싱하면서 식당별 리스트에 추가하는 방식이기 때문에, 불변 객체로 한 번에 생성하려면 전체를 먼저 분류한 뒤 생성해야 하는 불필요한 중간 버퍼가 생깁니다.
- API 응답의 한국어 식당 키 (`"기숙사 식당"`, `"학생 식당"`, `"교직원 식당"`)는 `Cafeteria.fromApiKey()`로 매핑합니다.
- `parseRawMeal`은 본래 `api_v2.dart`에 있었으나 도메인 책임을 명확히 하기 위해 `meal.dart`로 이동했습니다 (`0d331a2`).

## 커스텀 스크롤 시스템

**해결하는 문제:** Flutter의 `PageView`(수평 스와이프)와 그 안에 중첩된 `ListView`(수직 스크롤) 사이에서 발생하는 제스처 충돌 — 수직에 가까운 스와이프가 내부 스크롤에 빼앗기거나, 수평 스와이프가 외부 PageView로 넘어가지 못하는 현상을 처리합니다.

`lib/pages/home/nested_page_scroll.dart`는 끼니 간 가로 스와이프(PageView)와 카드 내부 세로 스크롤을 통합 처리하는 `NestedPageScrollController` / `NestedPageScrollView` / `NestedPageScrollControllerGroup`을 정의합니다. 코드베이스에서 가장 복잡한 부분이므로 수정 전 자세한 분석은 [`docs/nested_page_scroll_analysis.md`](nested_page_scroll_analysis.md)와 파일 내 주석을 참고하세요.

## 주요 의존성

| 패키지 | 용도 |
|---|---|
| `provider` | `AppSettings` ChangeNotifier를 위젯 트리에 공급 |
| `http` | HTTP 클라이언트 기반 인터페이스 |
| `cupertino_http` | iOS 네이티브 NSURLSession 기반 클라이언트 |
| `cronet_http` | Android Cronet 기반 클라이언트 (HTTP/3 지원) |
| `shared_preferences` | 설정 값 영속화 |
| `flutter_svg` | 사이드바 로고(`bapu_logo.svg`) 렌더링 |
| `flutter_localizations` + `intl` | 한국어/영어 다국어 지원 |

## 디렉터리 구조

```
lib/
├── main.dart                          앱 진입점, ChangeNotifierProvider, MaterialApp
├── constants.dart                     ApiConstants, MealTimeConfig, StorageKeys
├── meal.dart                          도메인 타입 + parseRawMeal
├── model.dart                         HomePageModel
├── api_v2.dart                        HTTP 호출, JSON 파싱
├── announcement_service.dart          공지 확인 + 비교 (테스트 가능 분리)
├── data.dart                          캐시 정책 + fetch-and-cache
├── storage.dart                       조건부 export
├── storage_io.dart / storage_web.dart 플랫폼별 캐시 구현
├── platform_http_client.dart          조건부 export
├── platform_http_client_io.dart       Cupertino / Cronet 클라이언트
├── platform_http_client_web.dart      웹 클라이언트
├── l10n/                              ARB + 자동 생성된 AppLocalizations
├── settings/
│   ├── app_settings.dart              AppSettings ChangeNotifier
│   ├── allergy_settings.dart          AllergySettings 값 객체
│   ├── notification_settings.dart     NotificationSettings 값 객체
│   └── widget_settings.dart           WidgetSettings 값 객체
└── pages/
    ├── home.dart                      home_page barrel export
    ├── home_drawer.dart               드로어, 공지 다이얼로그, 설정 진입점
    ├── settings_page.dart             설정 화면 (테마 / 알레르기 / 알림 / 위젯)
    ├── allergy_selection_page.dart    19개 알레르겐 체크리스트
    └── home/
        ├── home_page.dart             메인 화면, FutureBuilder 체인
        ├── home_app_bar.dart          AppBar (끼니 스위치 / 요일 탭 / 날짜)
        ├── meal_card.dart             식당별 메뉴 카드
        ├── week_meal_view.dart        요일 탭뷰 + 반응형 카드 테이블
        └── nested_page_scroll.dart    중첩 스크롤 시스템
```

## 테스트

- `test/domain_test.dart` — 도메인 모델 / 파싱 로직 단위 테스트
- `test/announcement_service_test.dart` — 공지 비교·저장 로직 단위 테스트
- `test/settings_test.dart` — `AppSettings` 및 값 객체 단위 테스트
- `test/widget_test.dart` — 앱 렌더링 / 테마 스모크 테스트

미커버 영역: `nested_page_scroll.dart` 제스처 상호작용, 웹 플랫폼 전용 분기(`storage_web.dart`).

테스트 설명은 한국어로 작성합니다.

## 컨벤션

- 코드 주석: 한국어
- 커밋 메시지: 영어 (복잡한 경우 한국어 허용)
- 테스트 설명: 한국어
- AI 도구용 plan/spec: 영어
- l10n 키: 영어 / 값: 한국어·영어
- 폰트: Pretendard (`assets/fonts/`에 번들)
- 주 색상: `#00CD80` (`mainColor`, `lib/main.dart`)
