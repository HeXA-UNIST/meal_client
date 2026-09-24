# 아키텍처

밥먹어U(`meal_client`)의 현재 코드 구조와 주요 데이터 흐름을 정리한 문서입니다. 작업 규칙은 루트의 [AGENTS.md](../AGENTS.md), 실행 명령은 [README.md](../README.md)를 참고하세요. 실제 동작을 변경할 때는 이 문서보다 소스와 테스트를 우선 확인합니다.

## 전체 구조

```
ChangeNotifierProvider<AppSettings> ──► BapUApp ──► HomePage
                                                    ├─ 식단·안내 정보 갱신, 공지 비교
                                                    └─ WeekMenuScaffold ──► 요일/끼니 선택, 카드
                                                         ▲
HomePageDrawer ──► NextWeekPreviewPage ──────────────────┘
               └─► SettingsPage ──► 알레르기·알림 설정

/v2/menu ──► MealRefreshService ──► meal.json / meal-next.json
/v2/info ──► InfoRefreshService ──► info.json
                  │                   │
                  └─ Flutter 화면 ◄───┘
                     Android 위젯 / iOS WidgetKit은 공유 캐시를 읽음

AppSettings / Workmanager ──► 알림 예약 조정 ──► OS 로컬 알림
Flutter 갱신 ──► widget_service ──► Android render bridge / iOS timeline reload
```

## 레이어 개요

명시적인 저장소 패턴은 두지 않고, 화면이 데이터 소스를 직접 호출합니다. 아래 구분은 코드 탐색을 위한 것입니다.

```
UI 레이어        → lib/features/home/ (home_page, week_menu_scaffold,
                                       next_week_preview_page, week_meal_view 등)
                  lib/features/settings/ (settings_page, allergy/, notification/)
상태 / 도메인    → lib/features/home/model.dart (HomePageModel),
                  lib/domain/meal.dart (도메인 타입),
                  lib/core/constants.dart,
                  lib/features/settings/ (AppSettings + 값 객체)
i18n             → lib/l10n/ (app_ko.arb, app_en.arb, 자동 생성된 AppLocalizations)
데이터 / 인프라  → lib/features/info/, lib/features/meal/, lib/features/notification/,
                  lib/features/widget/widget_service*.dart,
                  lib/core/widget_shared_storage*.dart,
                  lib/core/network/
네이티브 위젯    → android/app/src/main/kotlin/.../meal_client/BapUWidget*.kt,
                  plugins/bapu_widget_bridge/,
                  ios/Runner/AppDelegate.swift (App Group / WidgetKit bridge),
                  ios/BapUWidget/BapUWidget.swift
```

## 핵심 컴포넌트

| 컴포넌트 | 파일 | 책임 | 상태 접근 |
|---|---|---|---|
| `BapUApp` | `main.dart` | MaterialApp 구성, 테마 적용 | `AppSettings.themeMode` 선택 구독 |
| `HomePage` | `features/home/home_page.dart` | 현재 주 식단·안내 정보 로딩, 공지 확인, 주차 전환 | `WeekMenuScaffold`에 Future 전달 |
| `WeekMenuScaffold` | `features/home/week_menu_scaffold.dart` | 현재 주/미리보기 공통 Scaffold, FutureBuilder, 요일·끼니 선택 상태 | `HomePageModel`, `ValueNotifier<MealOfDay>` 소유 |
| `NextWeekPreviewPage` | `features/home/next_week_preview_page.dart` | `nextWeekStart` 확인 후 지정 주 식단 로딩 | `WeekMenuScaffold` 재사용 |
| `HomeAppBar` 구성요소 | `features/home/home_app_bar.dart` | 날짜 제목, 요일 탭, 끼니 전환 버튼 | 끼니 버튼이 `ValueNotifier<MealOfDay>` 구독 |
| `WeekMealTabBarView` | `features/home/week_meal_view.dart` | 요일 탭뷰 + 반응형 카드 테이블, 식단 카드 운영시간 연결 | `Future<AppInfo>` read |
| `NestedPageScrollView` | `features/home/nested_page_scroll.dart` | 끼니 간 세로 PageView + 카드 내 세로 스크롤 통합 | — |
| `MealCard` | `features/home/meal_card.dart` | 식당별 메뉴 카드 표시, 운영시간/칼로리 표시, 공유 | — |
| `HomePageDrawer` | `features/home/home_drawer.dart` | 공지·운영시간 다이얼로그, 설정·다음 주 미리보기 진입점 | `Future<AppInfo>`, `Future<String?>` 사용 |
| `SettingsPage` | `features/settings/settings_page.dart` | 설정 화면 (테마/언어/알레르기/알림 등) | `AppSettings` read/watch |
| `AllergySettingsPage` | `features/settings/allergy/allergy_settings_page.dart` | 알레르겐 체크리스트 | `AppSettings` read/write |
| `NotificationSettingsPage` | `features/settings/notification/notification_settings_page.dart` | 메뉴 알림 설정 | `AppSettings` read/write |
| `AppSettings` | `features/settings/app_settings.dart` | 앱 전역 설정 상태 소유 + SharedPreferences 영속화 | ChangeNotifier Provider 루트 배치 |

### 위젯 트리 (런타임)

```
BapUApp
└─ MaterialApp (themeMode ← AppSettings)
   └─ HomePage (StatefulWidget)
      └─ WeekMenuScaffold
         ├─ AppBar → 날짜 / 끼니 전환 버튼 / 요일 탭
         ├─ Drawer → HomePageDrawer
         │             ├─ SettingsPage → AllergySettingsPage / NotificationSettingsPage
         │             └─ NextWeekPreviewPage → WeekMenuScaffold
         └─ Body (FutureBuilder: cachedMeal → downloadedMeal)
             └─ WeekMealTabBarView (TabBarView × 7일)
                 └─ NestedPageScrollView (PageView × 3끼니)
                     └─ MealCard × 3 (기숙사 / 학생 / 교직원)
```

## 상태 관리

화면 선택 상태와 앱 전역 설정이 분리되어 있습니다.

- **`HomePageModel`** (`lib/features/home/model.dart`)
  화면 로컬 선택 상태(현재 끼니, 요일 등). 평범한 가변 객체이며 `_WeekMenuScaffoldState`가 소유합니다. 끼니 버튼 상태는 `ValueNotifier<MealOfDay>`로 분리해 버튼 중심으로 리빌드 범위를 좁혔습니다.

- **`AppSettings extends ChangeNotifier`** (`lib/features/settings/app_settings.dart`)
  앱 전역 사용자 설정의 단일 소유자입니다. 루트에 `ChangeNotifierProvider<AppSettings>`가 한 번만 배치되며, `context.watch/read/select`로 접근합니다. `SharedPreferences` 영속화와 알림 예약 조정을 담당합니다.

  서브 설정은 모두 불변 값 객체입니다.
  - `AllergySettings` (`lib/features/settings/allergy/allergy_settings.dart`) — 선택한 알레르겐 ID 집합
  - `NotificationSettings` (`lib/features/settings/notification/notification_settings.dart`) — 알림 on/off, 키워드, 시간대별 시각, 요일, 식당·기숙사 메뉴 종류
  - `ThemeMode` — Flutter 표준 enum 그대로 사용

  알림 설정 변경은 저장·권한 확인·네이티브 예약 조정으로 이어집니다. 앱의 활성화 설정과 OS 알림 권한은 별도로 관리합니다. Android 홈 화면 위젯은 네이티브 설정 Activity를, iOS 위젯은 인스턴스별 식당을 고르는 App Intent를 사용합니다.

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

API URL, 일부 저장 키와 끼니 시간 기준은 `lib/core/constants.dart`에 있습니다.

- `ApiConstants` — 백엔드 엔드포인트 URL
- `MealTimeConfig` — 끼니 시간 경계 및 `determineMealOfDay()` 로직
- `StorageKeys` — `SharedPreferences` 키와 캐시 파일 이름
  - raw 공유 캐시: `mealCacheFile`(`meal.json`), `nextMealCacheFile`(`meal-next.json`), `infoCacheFile`(`info.json`)
  - 공지 비교: `announcementKey`
  - 설정: `settings_*` prefix (`allergenIds`, `notificationEnabled`, `notificationMutationGeneration`, `notificationKeywords`, `notificationPeriodTimePrefix`, `notificationPeriodRememberedPrefix`, `notificationDays`, `notificationCafeterias`, `notificationDormMenuTypes`, `themeMode` 등)

## 데이터 흐름

### 식단 데이터 로딩 흐름

```
앱 시작
  │
  ├─► getCachedMealData() ──► 현재 KST 주의 meal.json, 없으면 meal-next.json
  │                            └─ 일치하는 주가 있으면 먼저 표시
  └─► 캐시 읽기 종료 후 fetchAndCacheCanonicalMealData()
       ├─ /v2/menu 응답 검증 → meal.json 저장 → 위젯 갱신
       ├─ nextWeekStart가 있으면 다음 주 식단 선반입 → meal-next.json
       └─ 식단 갱신 후 알림 예약 재조정

HomePage의 두 Future ──► WeekMenuScaffold의 FutureBuilder ──► 화면 갱신
```

### 화면 갱신과 주차 전환

`HomePage`는 캐시 읽기를 시작하고, 캐시가 성공하거나 실패한 뒤 현재 주 네트워크 갱신을 실행합니다. `WeekMenuScaffold`가 두 Future를 받아 캐시를 먼저 표시하고 새 응답으로 교체합니다. 앱이 다시 활성화됐을 때 KST 주 ID가 달라졌으면 로딩을 재시작합니다. `nextWeekStart`는 오래된 캐시가 아닌 새 `/v2/menu` 응답에서 추출합니다.

| 상태 | UI 동작 |
|---|---|
| 캐시 로딩 중 | 스피너 |
| 캐시 성공, 네트워크 로딩 중 | 캐시 데이터 표시 (최신 아닐 수 있음) |
| 네트워크 성공 | 최신 데이터로 자동 갱신 |
| 캐시 실패, 네트워크 로딩 중 | 스피너 |
| 캐시 + 네트워크 모두 실패 | `l10n.cannotLoadMeal` 텍스트 |
| 네트워크만 실패 | 캐시 데이터 유지 (에러 숨김) |

서랍의 다음 주 미리보기는 `nextWeekStart`를 확인한 뒤 `/v2/menu/{weekStart}`를 요청하고 `meal-next.json`에 저장합니다. 미리보기와 현재 주 화면은 `WeekMenuScaffold`를 공유합니다.

### 앱 정보(`/v2/info`) 로딩 흐름

`HomePage`는 화면용 안내 정보를 `info.json` 캐시에서 먼저 읽고 새 `/v2/info` 결과로 교체합니다. 공지의 새 버전 판정에는 캐시가 아닌 별도의 새 응답 Future를 사용합니다. 화면용 `Future<AppInfo>`는 다음 두 곳에서 공유됩니다.

| 소비자 | 사용 목적 |
|---|---|
| `HomePageDrawer` | 공지사항 수동 확인, 운영시간 다이얼로그 표시 |
| `WeekMealTabBarView` | 선택한 날짜/끼니/식당의 운영시간을 식단 카드에 전달 |

`fetchAppInfo()`는 `InfoRefreshService.refreshInfo()`를 호출합니다. 서비스는 캐시 본문의 `last_modified`로 `If-Modified-Since` 조건부 요청을 보내고, 304면 검증된 캐시를 사용합니다. 200 응답은 파싱·검증 후 공유 `info.json`에 저장합니다. Android/iOS 위젯도 이 파일에서 운영시간을 읽습니다.

공지사항과 운영시간 다이얼로그는 `SelectionArea`로 감싸져 있어 제목과 본문 텍스트를 선택/복사할 수 있습니다.

### 공유 캐시와 무효화

`meal.json`, `meal-next.json`, `info.json`은 앱, background refresh, native 위젯이 공유하는 raw JSON 캐시입니다. `core/widget_shared_storage.dart`가 저장 위치를 고릅니다. `meal-next.json`은 다음 주 식단 선반입 파일이며, 자정에 이름을 바꿔 승격하지 않습니다. 쓰기는 임시 파일을 최종 파일로 교체하며, iOS 백업 제외 속성은 최종 파일에 적용합니다.

- Android: `getApplicationSupportDirectory()`와 native `context.filesDir`가 같은 앱 내부 디렉터리를 가리킵니다.
- iOS: native bridge가 반환하는 App Group 컨테이너를 사용합니다. Dart에는 App Group ID를 하드코딩하지 않습니다.
- Web: 공유 파일 캐시가 없으므로 stub이 예외/no-op로 동작합니다.

식단 캐시의 주차 정체성은 파일 수정 시각이 아니라 payload의 `week.startDate`입니다. Dart, Android, iOS는 현재 KST 주의 월요일과 일치하는 파일을 선택하며, 두 파일 모두 일치하면 `meal.json`을 우선합니다. 일치하는 파일이 없으면 이전 주 메뉴를 표시하지 않습니다. 수정 시각은 `meal-next.json`을 KST 일요일에 이미 갱신했는지 판단할 때만 사용합니다.

`info.json`은 별도 주차 freshness 판정이 없습니다. `/v2/info`가 200이면 raw 응답으로 갱신하고 304이면 기존 캐시를 유지합니다. Android 위젯은 파일이 없거나 깨졌거나 필요한 운영시간이 없으면 운영상태를 표시하지 않습니다.

### 백그라운드 새로고침

`native_startup_io.dart`는 `meal_notification_worker.dart`의 단일 `callbackDispatcher`로 Workmanager를 초기화합니다. 주기 refresh task 이름은 `bapu_meal_refresh`이고 등록 주기는 1시간입니다. 메뉴 알림은 Workmanager의 별도 전송 task가 아니라 Android/iOS OS에 미리 예약한 로컬 알림입니다.

background dispatcher는 다음 순서로 동작합니다.

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `DartPluginRegistrant.ensureInitialized()`
3. meal/info refresh를 병렬 실행
4. 치명적 cache refresh 실패가 없으면 `refreshWidgets(throwOnFailure: true)` 실행
5. 지원 플랫폼에서 저장 설정과 캐시를 다시 읽고 로컬 알림 예약 조정

meal refresh 실패, info cache write 실패, native render bridge 실패, 알림 예약 조정 실패는 task failure입니다. meal cache가 갱신된 뒤의 `/v2/info` fetch/parse 실패만 기존 info cache를 유지하며 비치명적으로 처리합니다. Android는 WorkManager `NetworkType.connected` 제약을 사용합니다. iOS BGTaskScheduler는 동일한 네트워크 제약을 보장하지 않으며, 실행 시점도 시스템 정책에 좌우됩니다.

### 메뉴 알림

`AppSettings`는 알림 설정과 OS 권한 상태를 별도로 관리합니다. 설정 변경, 앱 재개, foreground 식단 갱신, background refresh 뒤에는 `NotificationScheduleCoordinator`가 작업을 직렬화하고 `scheduled_meal_notifications.dart`가 현재 주와 다음 주 캐시에서 예약 목록을 계산합니다. `notification_service.dart`는 `flutter_local_notifications`로 Android/iOS의 one-shot 알림을 예약·취소합니다. 키워드 필터는 현재 Debug 빌드에서만 활성화됩니다.

예약 목록은 저장 설정의 시간대·요일·식당·기숙사 메뉴 종류와 실제 식단으로 결정합니다. background isolate는 설정과 캐시 revision을 다시 읽어 변경이 겹쳤는지 확인한 뒤 예약을 조정합니다. 따라서 알림 동작을 수정할 때는 설정 화면, `AppSettings`, 영속화, 예약 계산, 플랫폼 서비스, background worker를 함께 추적해야 합니다.

### 홈 화면 위젯

#### Android

Android 홈 화면 위젯은 `android/app/src/main/kotlin/pro/hexa/meal/meal_client/` 아래 네이티브 provider로 구현되어 있습니다.

핵심 구조:

| 파일 | 역할 |
|---|---|
| `BapUWidgetContract.kt` | cache 파일명, API enum, KST/끼니 경계, 식당/끼니 enum |
| `BapUWidgetTime.kt` | KST 현재 끼니, day api key, KST week id |
| `BapUWidgetMealParser.kt` | `/v2/menu` raw JSON → `WidgetMealData` parser (`REGULAR` only, 영어 fallback) |
| `BapUWidgetMealRepository.kt` | `meal.json` / `meal-next.json` cache-only read/freshness |
| `BapUWidgetOperatingHours.kt` | `info.json` cache-only read, 운영상태 계산, scheduler periods |
| `BapUWidgetUpdateDispatcher.kt` | 모든 provider 렌더 공통 진입점 |
| `BapUWidgetScheduleManager.kt` | AlarmManager 경계 예약 |
| `BapUWidgetDataHelper.kt` | 설정 SharedPreferences, layout/fitting, RemoteViews helper |

Android 위젯은 네트워크를 직접 호출하지 않습니다. `meal.json`이 현재 KST 주와 맞지 않으면 `meal-next.json`을 확인하고, 두 파일 모두 유효한 현재 주 식단이 없으면 `info.json`으로 계산한 현재 끼니의 빈 메뉴 상태를 렌더합니다. `info.json`이 없거나 corrupt이거나 breakfast/lunch 전환 계산에 필요한 운영시간이 없으면 고정 경계로 대체하지 않고 위젯 데이터 오류를 표시합니다. 데이터 갱신은 Dart foreground/background refresh가 담당합니다.

표시 전환은 AlarmManager의 inexact one-shot으로 처리합니다. 예약 경계는 자정, `info.json`에서 계산한 끼니 전환 시각(오늘 모든 식당의 breakfast/lunch 중 가장 늦은 종료 시각 + 1분), 모든 운영 시작, 마감임박 시작(종료 45분 전), 모든 운영 종료입니다. 마감임박은 분 단위 카운트다운 없이 coarse 상태로 표시하며, 시스템 절전 정책에 따라 실제 갱신은 경계보다 늦을 수 있습니다. provider XML의 `updatePeriodMillis`는 `0`이며, 순수 native 주기 안전망이 필요해질 때만 다시 검토합니다.

`BapUWidgetUpdateWorker`는 legacy WorkManager class 이름을 보존해 기존 예약이 missing class가 되지 않게 하는 shim입니다. active render path가 아니며, 실행되면 legacy unique work를 cancel하고 성공 종료합니다.

Android render bridge는 로컬 Flutter plugin `plugins/bapu_widget_bridge`가 담당합니다. foreground Activity가 없어도 background/headless engine에서 MethodChannel handler가 등록될 수 있도록 application context를 사용하고, `BapUWidgetUpdateDispatcher.renderAllWidgets()`를 호출합니다.

#### iOS WidgetKit

`ios/BapUWidget/`에 `systemMedium` WidgetKit extension과 `AppIntentTimelineProvider`가 구현되어 있습니다. 현재 시각과 운영시간으로 끼니를 자동 선택하고, 각 위젯 인스턴스는 `BapUWidgetConfigurationIntent`로 기숙사 한식·기숙사 할랄·학생·교직원 식당 중 하나를 선택합니다.

- `ios/Runner/AppDelegate.swift`: App Group path 조회 channel(`pro.hexa.meal.meal_client/widget_shared_storage`)과 WidgetKit reload channel(`pro.hexa.meal.meal_client/widget`) 등록
- `ios/Runner/Runner.entitlements`: Runner App Group capability
- `ios/BapUWidget/BapUWidget.entitlements`: extension App Group capability
- `ios/Runner.xcodeproj/project.pbxproj`: `APP_GROUP_IDENTIFIER = group.com.wjddnwls7879.unistbab`
- `lib/core/widget_shared_storage_io.dart`: iOS에서 native bridge로 App Group container path 조회

WidgetKit은 Android AlarmManager처럼 분 단위 갱신을 보장하지 않으므로 timeline entry에 자정, `info.json`에서 계산한 끼니 전환 시각, 운영 시작, 종료 45분 전의 coarse 마감임박 시작, 운영 종료를 미리 넣습니다. 한 timeline 생성 중에는 App Group cache를 파일별로 한 번만 읽어 모든 entry가 같은 입력을 공유하고, 전체 entry를 제공한 뒤 `.atEnd`에서 다음 timeline을 요청합니다.

## 플랫폼 분기

조건부 export로 플랫폼별 구현을 선택합니다. 저장소와 HTTP 클라이언트는 `dart.library.js_interop`, 네이티브 서비스와 알림 플랫폼 식별은 `dart.library.io`를 사용합니다.

```dart
// core/widget_shared_storage.dart
export 'widget_shared_storage_io.dart'
    if (dart.library.js_interop) 'widget_shared_storage_web.dart';
```

| 진입 모듈 | 네이티브 | 웹 |
|---|---|---|
| `lib/core/widget_shared_storage.dart` | Android: app support/filesDir, iOS: App Group bridge | 공유 위젯 캐시 미지원 stub |
| `lib/features/widget/widget_service.dart` | Android/iOS MethodChannel render trigger | no-op stub |
| `lib/core/network/platform_http_client.dart` | iOS: `cupertino_http` / Android: `cronet_http` | 기본 `http` 패키지 |
| `lib/core/native_startup.dart` | Workmanager·로컬 알림 초기화 | no-op stub |
| `lib/features/notification/notification_platform.dart` | Android/iOS 플랫폼 식별 | 미지원 플랫폼 식별 |

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
- `Meal`은 `MealSection` 목록을 갖고, 섹션마다 종류·선택적 제목·`MealMenuItem(ko, en?)` 목록·선택적 kcal이 있습니다. UI는 각 섹션의 제목과 메뉴를 표시하며, 영어 값이 없으면 한국어로 대체합니다.
- `CafeteriaMeal.empty()`이 growable 리스트를 만들고, `parseRawMeal`이 그 리스트를 변이시켜 채우는 **2단계 초기화 패턴**입니다. API 응답을 순서대로 파싱하면서 식당별 리스트에 추가하는 방식이기 때문에, 불변 객체로 한 번에 생성하려면 전체를 먼저 분류한 뒤 생성해야 하는 불필요한 중간 버퍼가 생깁니다.
- `/v2/menu` 응답의 식당 키(`DORMITORY`, `STUDENT`, `FACULTY`), 요일 키(`MON`..`SUN`), 끼니 키(`BREAKFAST`, `LUNCH`, `DINNER`)는 각 도메인 enum으로 매핑합니다.
- `parseRawMeal`은 `REGULAR`, `CONVENIENCE`, `SPECIAL` 섹션을 파싱하고 `SALAD`와 알 수 없는 종류는 건너뜁니다. 카드에는 섹션 제목과 kcal이 표시되며, allergen 표시는 구현되어 있지 않습니다.

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
| `mealEndpointFor(date)` (`/v2/menu/{date}`) | 지정 주 식단 미리보기·선반입 | `features/meal/meal_refresh_service.dart` |
| `infoEndpoint` (`/v2/info`) | 공지사항 + 운영시간 | `features/info/info_data_source.dart` |
| `noticeEndpoint` (`/notice`) | 기존 공지 API 상수 | 현재 주요 흐름에서는 `/v2/info`의 `announcement` 사용 |

## 커스텀 스크롤 시스템

**해결하는 문제:** 끼니 간 세로 `PageView`와 각 페이지의 세로 `SingleChildScrollView` 사이에서 스크롤 입력을 이어서 처리합니다. 요일 간 이동은 바깥쪽 가로 `TabBarView`가 담당합니다.

`lib/features/home/nested_page_scroll.dart`는 끼니 간 세로 전환과 카드 영역의 세로 스크롤을 통합 처리하는 `NestedPageScrollController` / `NestedPageScrollView` / `NestedPageScrollControllerGroup`을 정의합니다. 수정 전에는 [상세 분석](features/nested_page_scroll.md)과 파일 내 주석을 함께 읽어야 합니다.

## 주요 의존성

| 패키지 | 용도 |
|---|---|
| `provider` | `AppSettings` ChangeNotifier를 위젯 트리에 공급 |
| `http` | HTTP 클라이언트 기반 인터페이스 |
| `cupertino_http` | iOS 네이티브 NSURLSession 기반 클라이언트 |
| `cronet_http` | Android Cronet 기반 클라이언트 (HTTP/3 지원) |
| `shared_preferences` | 설정 값 영속화 |
| `workmanager` | Android/iOS background refresh 등록 |
| `flutter_local_notifications` + `timezone` | Android/iOS 로컬 알림 예약 |
| `bapu_widget_bridge` (local) | Android background-safe widget render MethodChannel |
| `flutter_svg` | 사이드바 로고(`bapu_logo.svg`) 렌더링 |
| `flutter_localizations` + `intl` | 한국어/영어 다국어 지원 |
| `material_ui` + `cupertino_ui` | Flutter Material/Cupertino UI 구성 |

## 디렉터리 구조

```
lib/
├── main.dart                              앱 진입점, ChangeNotifierProvider, MaterialApp
├── core/
│   ├── constants.dart                     ApiConstants, MealTimeConfig, StorageKeys
│   ├── native_startup.dart                네이티브 서비스 초기화 조건부 export
│   ├── native_startup_io.dart             Workmanager 및 로컬 알림 초기화
│   ├── native_startup_stub.dart           웹 stub
│   ├── widget_shared_storage.dart         raw widget cache 조건부 export
│   ├── widget_shared_storage_io.dart      Android filesDir / iOS App Group shared cache
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
│   │   ├── home_page.dart                 현재 주 데이터 로딩·공지·주차 전환
│   │   ├── home_app_bar.dart              AppBar (끼니 스위치 / 요일 탭 / 날짜)
│   │   ├── home_drawer.dart               드로어, 다이얼로그, 설정·미리보기 진입점
│   │   ├── meal_card.dart                 식당별 메뉴 카드, 운영시간/칼로리 표시
│   │   ├── model.dart                     HomePageModel
│   │   ├── nested_page_scroll.dart        중첩 스크롤 시스템
│   │   ├── week_meal_view.dart            요일 탭뷰 + 반응형 카드 테이블
│   │   ├── week_menu_scaffold.dart        현재 주/미리보기 공통 화면과 선택 상태
│   │   └── next_week_preview_page.dart    지정 주 식단 미리보기
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
│   │   ├── meal_background_refresh_io.dart Workmanager background refresh
│   │   ├── meal_background_refresh_stub.dart
│   │   └── meal_data_source.dart          식단 loading facade
│   ├── widget/
│   │   ├── widget_service.dart            조건부 export
│   │   ├── widget_service_io.dart         Android/iOS render MethodChannel
│   │   └── widget_service_stub.dart       Web/no-op
│   ├── notification/
│   │   ├── meal_notification_period.dart  시간대/대상 끼니
│   │   ├── meal_notification_content_builder.dart   메뉴별 알림 내용
│   │   ├── meal_notification_mutation_lock.dart     예약 변경 직렬화
│   │   ├── meal_notification_worker.dart            Workmanager dispatcher + 캐시/예약 갱신
│   │   ├── notification_scheduler.dart              예약 coordinator
│   │   ├── scheduled_meal_notifications.dart        캐시 기반 예약 목록·조정
│   │   ├── notification_service.dart                Android/iOS 로컬 알림
│   │   └── notification_platform*.dart              플랫폼 조건부 export
│   └── settings/
│       ├── app_settings.dart              AppSettings ChangeNotifier
│       ├── settings_page.dart             설정 화면
│       ├── allergy/                      알레르기 설정 화면·값 객체
│       └── notification/                 알림 설정 화면·값 객체·저장소
└── l10n/                                  ARB + 자동 생성된 AppLocalizations

android/app/src/main/kotlin/pro/hexa/meal/meal_client/
├── BapUBaseWidgetProvider.kt              공통 AppWidgetProvider lifecycle base class
├── BapUWidget2x2Provider.kt               2x2 단일 식당 provider
├── BapUWidgetContract.kt                  native/Dart/API drift-sensitive contract
├── BapUWidgetTime.kt                      KST time helpers
├── BapUWidgetFetcher.kt                   WidgetMealData 정의 + cache-only fetch 진입점
├── BapUWidgetMealParser.kt                /v2/menu raw JSON parser
├── BapUWidgetMealRepository.kt            meal.json / meal-next.json cache-only repository
├── BapUWidgetOperatingHours.kt            info.json operating status
├── BapUWidgetDataHelper.kt                설정 SharedPreferences, layout/fitting, RemoteViews helper
├── BapUWidgetSingleConfigActivity.kt      단일 식당 위젯 설정 화면
├── BapUWidgetUpdateDispatcher.kt          render entrypoint
├── BapUWidgetScheduleManager.kt           AlarmManager display boundaries
├── BapUWidgetScheduledUpdateReceiver.kt   예약 알람 수신 후 전체 위젯 갱신
├── BapUWidgetBootReceiver.kt              부팅 후 다음 예약 복구
└── BapUWidgetUpdateWorker.kt              legacy WorkManager shim only

plugins/bapu_widget_bridge/
└── android/.../BapUWidgetBridgePlugin.java Android headless render bridge
```

## 테스트와 확인 경계

- `test/domain_test.dart`, `test/meal_card_test.dart` — 메뉴 파싱·섹션 표시
- `test/home_page_test.dart`, `test/week_menu_scaffold_test.dart`, `test/next_week_preview_page_test.dart` — 현재 주·미리보기 로딩과 화면 상태
- `test/features/meal/`, `test/features/info/`, `test/core/widget_shared_storage_io_test.dart` — 식단·안내 정보 캐시와 공유 파일
- `test/features/notification/`, `test/settings_test.dart`, `test/notification_settings_page_test.dart` — 알림 설정·예약·background 조정
- `ios/BapUWidgetTests/BapUWidgetTests.swift`, `android/app/src/test/kotlin/.../BapUWidget*Test.kt` — 네이티브 위젯 캐시·시간·레이아웃 계산

실제 launcher의 RemoteViews 렌더링, WidgetKit 기기 동작, iOS App Group 서명, OS 알림 전달 시각은 각각 기기 확인이 필요합니다. 개발 명령은 [README.md](../README.md)를 따릅니다.
