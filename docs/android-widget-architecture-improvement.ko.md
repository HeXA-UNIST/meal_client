# 네이티브 위젯 cache-only 구조 개선 제안

## 목적

이 문서는 Android 네이티브 위젯을 중심으로 현재 구조를 분석하고, iOS WidgetKit 확장을 대비한 cache-only 리팩터링 범위를 제안한다. 필수 Phase 0-5의 구현 대상은 Android이며, iOS 내용은 Dart 저장/렌더 seam을 미리 흔들리지 않게 잡기 위한 대비 범위다.

핵심 방향은 “파일을 많이 나누는 것”이 아니라 다음 다섯 가지다.

1. Dart 앱과 native 위젯 사이에서 drift가 나면 실제 버그가 되는 계약을 한곳에 모은다.
2. 시간·운영시간·식단 파싱처럼 단위 테스트 가치가 높은 로직을 Android framework 의존 코드에서 분리한다.
3. RemoteViews/실측 layout처럼 시각 회귀 위험이 큰 코드는 필수 범위에서 제외하고, 별도 후속 작업으로 다룬다.
4. Flutter 앱은 `/v2/info` 운영시간을, 위젯은 하드코딩 운영시간을 쓰는 현재 구조는 운영상태 오표시라는 실제 사용자 버그를 유발하므로, `/v2/info` 운영시간 반영을 필수 범위에 포함한다.
5. Android 위젯은 native network fallback 없이 cache-only로 렌더링한다. 메뉴/운영시간 fetch와 cache write는 Dart가 단일 소유자가 되고, Dart background refresh가 cache를 갱신한 뒤 native 위젯 렌더를 호출한다.

## 현재 코드 지도

Android 위젯 관련 Kotlin 코드는 `android/app/src/main/kotlin/pro/hexa/meal/meal_client/` 아래에 있다.

| 파일 | 현재 책임 |
| --- | --- |
| `BapUWidgetFetcher.kt` | `meal.json` 캐시 읽기, 캐시 freshness, `/v2/menu` HTTP fallback, JSON 파싱, locale 기반 메뉴명 선택, `WidgetMealData` 정의 |
| `BapUWidgetDataHelper.kt` | 식당 상수, 위젯 설정 SharedPreferences, 현재 끼니 계산, 운영시간/운영상태 계산, 레이아웃 실측/텍스트 크기 계산, RemoteViews helper, launch intent |
| `BapUBaseWidgetProvider.kt` | 공통 AppWidgetProvider lifecycle, fetch 후 위젯 갱신, 스케줄러 보정 |
| `BapUWidget2x2Provider.kt` | 2x2 단일 식당 위젯 RemoteViews 바인딩 |
| `BapUWidget4x2DualProvider.kt` | 4x2 두 식당 위젯 RemoteViews 바인딩 |
| `BapUWidget4x2StatusProvider.kt` | 4x2 운영상태/두 열 메뉴 위젯 RemoteViews 바인딩 |
| `BapUWidget4x4Provider.kt` | 4개 식당 전체 위젯 RemoteViews 바인딩 |
| `BapUWidgetSingleConfigActivity.kt` | 단일 식당 위젯 설정 화면 |
| `BapUWidgetDualConfigActivity.kt` | 두 식당 위젯 설정 화면 |
| `BapUWidgetUpdateWorker.kt` | WorkManager 기반 전체 위젯 갱신, 15분 주기 작업 등록 |
| `BapUWidgetScheduleManager.kt` | 운영시간 경계/마감 임박 구간에 맞춘 AlarmManager 예약 |
| `BapUWidgetScheduledUpdateReceiver.kt` | 예약 알람 수신 후 전체 위젯 갱신 및 다음 예약 |
| `BapUWidgetBootReceiver.kt` | 부팅 후 위젯이 있으면 다음 예약 복구 |
| `MainActivity.kt` | Flutter MethodChannel에서 native widget refresh 요청 수신 |

## 현재 문제

### 1. `BapUWidgetDataHelper.kt`가 여러 책임을 가진다

`BapUWidgetDataHelper.kt`는 위젯 표시 helper라기보다 다음 책임이 섞인 파일이다.

- 식당 설정값: `CAFE_DORM_KOREAN`, `CAFE_DORM_HALAL`, `CAFE_STUDENT`, `CAFE_FACULTY`
- 설정 저장소: `getWidgetConfigPrefs()`, `loadSingleCafeteria()`, `saveDualCafeterias()` 등
- 시간 계산: `info.json` 기반 끼니 전환 계산, KST week id
- 운영시간 계산: `operatingPeriod()`, `getOperatingStatus()`
- 위젯 크기 계산: `widgetWidthDp()`, `widgetHeightDp()`, `calcMenuTextSp()`
- 메뉴 fitting: `truncateMenuByRealLayout()`, `splitMenuTwoColumnsByRealLayout()`
- Android UI helper: `RemoteViews.applyTextSizes()`, `RemoteViews.bindFoodType()`
- launch intent 생성: `makeLaunchPendingIntent()`

다만 모든 책임을 각각 파일로 쪼갤 필요는 없다. 우선 분리할 대상은 테스트 가치가 높고 drift 위험이 큰 시간·운영시간·계약값이다. RemoteViews 관련 코드는 시각 검증 비용이 크므로 뒤로 미룬다.

### 2. Dart/native 계약이 분산되어 있다

다음 값들은 Dart 쪽 `StorageKeys`, `MealTimeConfig`, `domain/meal.dart`와 동일한 의미를 가져야 한다.

- 캐시 파일명: `meal.json`
- 운영시간 캐시 파일명: `info.json`
- KST timezone: `Asia/Seoul`
- KST week id 기준
- 끼니 경계: 09:20, 13:30
- API enum: `DORMITORY`, `STUDENT`, `FACULTY`, `BREAKFAST`, `LUNCH`, `DINNER`, `KOREAN`, `HALAL`, `REGULAR`
- 요일 enum: `MON` ... `SUN`

API endpoint URL은 Dart fetch layer의 계약이다. cache-only 최종 구조에서 native widget은 `/v2/menu` 또는 `/v2/info` endpoint URL을 알 필요가 없다.

계약 파일을 만드는 것만으로 drift가 자동 감지되지는 않는다. 따라서 계약 분리와 함께 Kotlin unit test를 추가해야 한다.

### 3. `Int` 기반 식당/끼니 모델이 오류에 약하다

현재 식당 설정값은 raw `Int`다.

```kotlin
const val CAFE_DORM_KOREAN = 0
const val CAFE_DORM_HALAL = 10
const val CAFE_STUDENT = 1
const val CAFE_FACULTY = 2
```

끼니도 `0=조식`, `1=중식`, `2=석식`이다. 기존 SharedPreferences 저장값 호환에는 유리하지만, `operatingPeriod(cafeteria: Int, mealOfDay: Int)` 같은 함수는 잘못된 값을 컴파일 시점에 막지 못한다.

해결 방향은 raw 저장값을 없애는 것이 아니라, 저장소 경계에서만 raw `Int`를 사용하고 내부 계산은 enum/value object로 처리하는 것이다.

### 4. Fetcher가 너무 많은 일을 한다

`BapUWidgetFetcher.kt`는 cache, HTTP, parser, repository orchestration을 모두 가진다.

다만 이 파일을 `Cache`, `ApiClient`, `Parser`, `Repository` 네 파일로 나누는 것은 현재 규모에서는 과하다. 최종 목표는 native HTTP fallback 자체를 제거하는 것이므로 `ApiClient` 파일은 만들지 않는다. parser는 테스트 가치가 높으므로 분리하고, cache freshness/read orchestration은 `Repository` 하나에 private 함수로 묶는 정도가 적절하다.

### 5. Provider의 RemoteViews 바인딩 반복은 있지만 즉시 분리 대상은 아니다

Provider들은 width/height 계산, status 계산, setup callback, fitting 호출 패턴을 반복한다. 구조상 공통화 여지는 있다.

하지만 이 영역은 `LayoutInflater`, `RemoteViews`, launcher widget rendering에 강하게 의존한다. 파일 이동만으로 테스트성이 크게 좋아지지 않고, 시각 회귀 위험이 있다. 따라서 필수 리팩터링 범위에서는 제외하고, Phase 1-5 완료 후 별도 작업으로 다룬다.

### 6. 운영시간 하드코딩은 실제 사용자 버그로 이어질 수 있다

Flutter 앱은 `/v2/info`의 운영시간을 사용하지만, Android 위젯은 Kotlin 하드코딩 운영시간을 사용한다.

서버 운영시간이 바뀌면 Flutter 앱의 카드 운영시간은 맞는데 Android 위젯의 운영 상태는 틀릴 수 있다. 이는 단순 구조 문제가 아니라 데이터 정합성 문제다.

해결은 위젯 운영시간을 `/v2/info` 기반으로 전환하고 하드코딩 운영시간 table을 **제거**하는 것이다. Phase 2에서 현재 하드코딩 계산을 테스트 가능한 `BapUWidgetOperatingHours`로 모으는 것은 전환을 위한 과도기이며, Phase 4에서 하드코딩 table 자체를 삭제하고 `/v2/info` cache를 유일한 source로 삼는다. cache가 없으면 틀린 값을 보여주는 대신 운영상태 표시를 생략한다.

## 권장 목표 구조

필수 범위는 아래 정도로 제한한다.

```text
android/app/src/main/kotlin/pro/hexa/meal/meal_client/
├── BapUWidgetContract.kt
├── BapUWidgetTime.kt
├── BapUWidgetOperatingHours.kt
├── BapUWidgetMealParser.kt
├── BapUWidgetMealRepository.kt
├── BapUWidgetUpdateDispatcher.kt
├── BapUWidgetDataHelper.kt
├── BapUWidgetFetcher.kt
└── BapUWidget*Provider.kt
```

파일별 의도:

| 파일 | 역할 |
| --- | --- |
| `BapUWidgetContract.kt` | native widget 계약 상수와 식당/끼니 enum. Dart/API와 동기화되어야 하는 값의 중심 |
| `BapUWidgetTime.kt` | KST, 현재 끼니, KST week id, 요일 API key 등 순수 시간 계산 |
| `BapUWidgetOperatingHours.kt` | `/v2/info` cache 기반 운영시간(하드코딩 table 없음), 운영 상태 계산, scheduler용 운영시간 목록 |
| `BapUWidgetMealParser.kt` | `/v2/menu` JSON을 `WidgetMealData`로 변환 |
| `BapUWidgetMealRepository.kt` | `meal.json` cache-only read/freshness orchestration. native HTTP/cache write 없음 |
| `BapUWidgetUpdateDispatcher.kt` | 모든 widget id에 대해 cache-only 데이터를 읽고 provider render를 호출하는 공통 진입점 |
| `BapUWidgetFetcher.kt` | 기존 call site 호환 facade. 내부는 repository로 위임 |
| `BapUWidgetDataHelper.kt` | 당장 분리하지 않는 RemoteViews/layout/config helper 유지 |

`/v2/info` 운영시간 반영(Phase 4)에는 native 파일 외에 두 가지가 더 필요하다.

- Dart 쪽: `/v2/info` 응답 raw JSON을 native가 읽는 공유 캐시 위치(`sharedWidgetCacheDir()` — Android `filesDir`, iOS App Group; iOS 위젯 확장 절 참조)에 `info.json`으로 저장하는 cache write. `meal.json`과 동일하게 temp-file + rename.
- Native 쪽: `info.json` 운영시간 parser. 별도 파일로 나누지 않고 우선 `BapUWidgetOperatingHours.kt` 내부에 두되, 커지면 `BapUWidgetInfoParser.kt`로 분리한다.
- Native update 쪽: 기존 `BapUWidgetUpdateWorker.updateAllWidgets()`/`hasAnyWidget()` 같은 유틸 책임은 WorkManager class에 묶어두지 않고 `BapUWidgetUpdateDispatcher.kt`로 옮긴다. 이 파일은 새 추상화가 아니라 WorkManager 제거 후에도 필요한 렌더 진입점이다.

`BapUWidgetDataHelper.kt`는 한 번에 깨끗하게 만들려고 하지 않는다. Phase 1-3에서 시간/운영시간/fetcher 일부가 빠지면 자연스럽게 작아진다. 이후에도 layout/helper가 남아 크다면 별도 작업으로 다룬다.

## 필수 제안

### 제안 1: `BapUWidgetContract.kt`에 계약과 모델을 함께 둔다

`Contract`와 `Models`를 굳이 별도 파일로 나누지 않는다. 현재 규모에서는 계약 상수와 enum을 한 파일에 두는 편이 낫다.

예시:

```kotlin
object BapUWidgetContract {
    const val MEAL_CACHE_FILE = "meal.json"
    const val INFO_CACHE_FILE = "info.json"
    const val KST_ZONE_ID = "Asia/Seoul"

    object Api {
        const val CAFETERIA_DORMITORY = "DORMITORY"
        const val CAFETERIA_STUDENT = "STUDENT"
        const val CAFETERIA_FACULTY = "FACULTY"

        const val TIME_BREAKFAST = "BREAKFAST"
        const val TIME_LUNCH = "LUNCH"
        const val TIME_DINNER = "DINNER"

        const val MENU_KOREAN = "KOREAN"
        const val MENU_HALAL = "HALAL"
        const val SECTION_REGULAR = "REGULAR"
    }

    object MealTime {
        const val BREAKFAST_END_MINUTES = 9 * 60 + 20
        const val LUNCH_END_MINUTES = 13 * 60 + 30
        const val CLOSING_SOON_THRESHOLD_MINUTES = 45
    }
}

enum class WidgetCafeteria(val prefValue: Int) {
    DORM_KOREAN(0),
    STUDENT(1),
    FACULTY(2),
    DORM_HALAL(10);

    companion object {
        fun fromPrefValue(value: Int): WidgetCafeteria =
            entries.firstOrNull { it.prefValue == value } ?: DORM_KOREAN
    }
}

enum class WidgetMealOfDay(val index: Int, val apiKey: String) {
    BREAKFAST(0, BapUWidgetContract.Api.TIME_BREAKFAST),
    LUNCH(1, BapUWidgetContract.Api.TIME_LUNCH),
    DINNER(2, BapUWidgetContract.Api.TIME_DINNER);

    companion object {
        fun fromIndex(index: Int): WidgetMealOfDay =
            entries.firstOrNull { it.index == index } ?: BREAKFAST
    }
}
```

기존 `CAFE_*` 상수는 바로 제거하지 않는다. 1차 migration에서는 compatibility alias로 남기거나, 저장소 함수 내부에서만 `prefValue`를 다루게 한다.

`/v2/menu` endpoint URL 상수는 최종 contract에 두지 않는다. Phase 1에서 기존 fetcher 이동 때문에 임시 상수로 둘 수는 있지만, Phase 3에서 native network fallback을 제거하면서 함께 삭제한다. native parser와 repository에는 API endpoint URL이 아니라 JSON enum key와 cache file 이름만 필요하다.

### 제안 2: 시간 계산을 순수 함수로 분리한다

새 파일: `BapUWidgetTime.kt`

포함할 책임:

- `KST` timezone 생성
- `mealOfDayForMinutes(nowMinutes: Int, transitions: WidgetMealTransitionMinutes): WidgetMealOfDay`
- production용 현재 끼니 계산은 `BapUWidgetOperatingHours.currentMealOfDay(hours, now)`에서 `info.json` 기반 transition을 주입한다.
- `kstWeekId(ms: Long): Long`
- `dayOfWeekApiKey(calendar: Calendar): String`

중요한 점은 production 함수가 내부에서 `Calendar.getInstance()`를 호출하더라도, 테스트 가능한 overload를 별도로 제공하는 것이다.

예시:

```kotlin
object BapUWidgetTime {
    fun mealOfDayForMinutes(
        nowMinutes: Int,
        transitions: WidgetMealTransitionMinutes,
    ): WidgetMealOfDay = when {
        nowMinutes <= transitions.breakfastEndMinutes ->
            WidgetMealOfDay.BREAKFAST
        nowMinutes <= transitions.lunchEndMinutes ->
            WidgetMealOfDay.LUNCH
        else -> WidgetMealOfDay.DINNER
    }
}
```

### 제안 3: 운영시간 계산을 주입 가능한 형태로 분리한다

새 파일: `BapUWidgetOperatingHours.kt`

현재 `getOperatingStatus()`는 내부에서 현재 시간을 다시 읽기 때문에 단위 테스트가 어렵다. 개선 후에는 `nowMinutes`를 인자로 받는 함수가 중심이 되어야 한다.

예시:

```kotlin
data class WidgetTimeOfDay(val hour: Int, val minute: Int) {
    val minutesSinceMidnight: Int get() = hour * 60 + minute
}

data class OperatingPeriod(
    val start: WidgetTimeOfDay,
    val end: WidgetTimeOfDay,
)

object BapUWidgetOperatingHours {
    fun period(cafeteria: WidgetCafeteria, meal: WidgetMealOfDay): OperatingPeriod?

    fun status(
        cafeteria: WidgetCafeteria,
        meal: WidgetMealOfDay,
        nowMinutes: Int,
    ): OperatingResult

    fun allPeriodsForBoundaryScheduling(): List<OperatingPeriod>
}
```

`BapUWidgetScheduleManager`는 `listOf(CAFE_DORM_KOREAN, CAFE_STUDENT, CAFE_FACULTY)` 같은 자체 목록을 갖지 말고, `allPeriodsForBoundaryScheduling()`을 호출한다.

### 제안 4: Parser와 Repository만 분리한다

Fetcher 4분할은 피한다. 목표는 다음 2개 파일이다. native widget은 최종적으로 cache-only이므로 `ApiClient`는 만들지 않는다.

```text
BapUWidgetMealParser.kt
BapUWidgetMealRepository.kt
```

`BapUWidgetMealParser.kt`:

- `/v2/menu` JSON 구조만 안다.
- `REGULAR` 섹션만 사용한다.
- 영어 locale이면 `en` 우선, 없으면 `ko` fallback.
- 칼로리는 홈 위젯 제품 범위가 아니므로 파싱하지 않는다.

`BapUWidgetMealRepository.kt`:

- 현재 요일/끼니/locale 계산
- `meal.json` cache read/freshness
- `BapUWidgetMealParser` 호출
- cache miss/stale/corrupt 시 `null` 반환
- native HTTP fetch와 cache write 없음

`loadFromFreshCache`는 repository 내부 private 함수로 둔다. `httpGet`, `fetchFromNetwork`, `writeCache`는 최종 구조에서 제거한다. Dart가 `meal.json` cache write의 단일 소유자다.

`BapUWidgetFetcher.fetch(context)`는 기존 provider 호출부를 깨지 않도록 facade로 유지한다. 단 cache-only에서는 `filesDir` 접근이 필수이므로 기존의 nullable `context: Context? = null` 시그니처를 **non-null `context: Context`로 좁힌다**. context 없이 호출하면 cache를 읽을 수 없어 항상 `null`이 되므로, nullable 기본값은 footgun이다.

```kotlin
object BapUWidgetFetcher {
    fun fetch(context: Context): WidgetMealData? =
        BapUWidgetMealRepository.fetch(context)
}
```

## 선택 제안

아래 항목은 구조 이득이 있지만 필수 범위에서는 제외한다.

### 선택 A: Layout metrics / menu fitting 분리

`widgetWidthDp`, `calcMenuTextSp`, `truncateMenuByRealLayout` 등은 분리 가능하다. 하지만 이 로직은 `LayoutInflater`/`measure`에 의존하므로 Android JVM unit test로 검증하기 어렵고, 실제 위젯 시각 회귀 가능성이 있다.

따라서 Phase 1-5 완료 후에도 `BapUWidgetDataHelper.kt`가 계속 과도하게 커져 있거나, provider layout 조정 작업이 예정되어 있을 때 별도 작업으로 진행한다.

### 선택 B: Panel binder 공통화

Provider 반복을 줄이기 위해 `WidgetPanelIds`, `BapUWidgetPanelBinder`를 둘 수 있다. 다만 4개 layout의 XML 구조와 view id가 달라 과한 generic renderer는 피해야 한다.

공통화 대상은 panel 하나의 header/status/menu binding 정도로 제한한다.

### 선택 C: Update coordinator 도입

업데이트 진입점이 많은 것은 사실이다. 갱신 경로(표시=AlarmManager, 데이터=Dart push, native periodic WorkManager 제거)는 필수 **Phase 5**에서 확정되므로, 그 위에서 진입점을 하나의 coordinator로 모으는 정리는 Phase 5 이후 **Follow-up 3**로 다룬다.

> `/v2/info` 운영시간 cache 연동은 이전 버전에서 선택 항목이었으나, 운영상태 오표시가 실제 사용자 버그이므로 필수 범위로 승격했다. → 아래 **Phase 4** 참조.
>
> 갱신 경로 단일화(native periodic WorkManager 제거와 cache-only render)도 필수 범위로 승격했다. → 아래 **Phase 5** 참조.

## 단계별 계획

### Phase 0: Android 단위 테스트 하네스 확립

목표:

- Kotlin 순수 로직을 `:app:testDebugUnitTest`에서 검증할 수 있게 한다.
- Android platform `org.json` stub 문제를 피한다.

현재 필요한 구성:

```kotlin
testImplementation("junit:junit:4.13.2")
testImplementation("org.json:json:20240303")
```

작업:

1. `android/app/src/test/kotlin/...` 테스트 디렉터리 유지
2. `BapUWidgetFetcherTest` 또는 새 parser test가 local unit test로 실행되는지 확인
3. `.\gradlew.bat :app:testDebugUnitTest`를 baseline 검증 명령으로 확정

이 phase가 없으면 Phase 1-3의 가치가 크게 줄어든다.

### Phase 1: Contract + enum 도입

목표:

- Dart/native drift 위험이 큰 상수와 raw int 모델을 한곳으로 모은다.
- 동작 변경은 최소화한다.

작업:

1. `BapUWidgetContract.kt` 추가
2. `WidgetCafeteria`, `WidgetMealOfDay` 추가
3. `BapUWidgetFetcher.kt`의 cache file, API enum literal을 contract 참조로 변경
4. 기존 `CAFE_*` 저장값 호환 유지
5. Kotlin test에서 contract 값 일부를 검증

권장 drift 방어 테스트:

- `MEAL_CACHE_FILE == "meal.json"`
- `INFO_CACHE_FILE == "info.json"`
- `BREAKFAST`, `LUNCH`, `DINNER` api key
- `DORMITORY`, `STUDENT`, `FACULTY` api key

Dart 값을 Kotlin test에서 직접 import할 수는 없으므로 완전 자동 동기화는 아니다. 하지만 같은 fixture/기대값을 양쪽 테스트에 두면 drift가 리뷰에서 드러난다.

### Phase 2: Time + operating hours 분리

목표:

- KST week id, `info.json` 기반 현재 끼니 계산, 운영상태 계산을 테스트 가능한 순수 로직으로 만든다.

작업:

1. `BapUWidgetTime.kt` 추가
2. `BapUWidgetOperatingHours.kt` 추가
3. `info.json` 기반 현재 끼니 계산 추가
4. `kstWeekId()` 이동
5. `operatingPeriod()`와 `getOperatingStatus()` 이동
6. `BapUWidgetScheduleManager`가 새 operating-hours API 사용

이 단계에서 옮기는 하드코딩 운영시간 table은 과도기다. Phase 4에서 `/v2/info` cache로 대체하며 완전히 삭제한다. 따라서 Phase 2에서는 하드코딩 값에 새 기능(예: weekend 분기)을 얹지 않는다. 최종 구현에서는 `info.json`이 필수 입력이며, 고정 끼니 경계로 대체하지 않는다.

테스트:

- `info.json`에서 계산한 breakfast 최종 종료 시각 -> 조식
- `info.json`에서 계산한 breakfast 최종 종료 + 1분 -> 중식
- `info.json`에서 계산한 lunch 최종 종료 시각 -> 중식
- `info.json`에서 계산한 lunch 최종 종료 + 1분 -> 석식
- 월요일 00:00 KST에서 week id 증가
- closing soon 45분 경계
- 운영 종료 시각부터 다음 전역 끼니 전환까지 closed 유지
- 기숙사 할랄은 기숙사 운영시간 공유

### Phase 3: Parser + repository 정리

목표:

- `/v2/menu` parser를 독립 테스트 가능한 단위로 만든다.
- fetcher orchestration은 cache-only repository로 옮기되 과분할하지 않는다.
- native widget의 `/v2/menu` network fallback을 제거한다.

작업:

1. `BapUWidgetMealParser.kt` 추가
2. 현재 `parseWidgetMealData`와 관련 helper 이동
3. parser test를 `BapUWidgetMealParserTest`로 정리
4. `BapUWidgetMealRepository.kt` 추가
5. cache read/freshness는 repository private 함수로 이동
6. `fetchFromNetwork`, `httpGet`, native `writeCache` 제거
7. native contract 또는 fetcher에 남아 있는 `/v2/menu` endpoint URL 상수 제거
8. cache miss/stale/corrupt 시 repository가 `null`을 반환하도록 정리
9. `BapUWidgetFetcher.fetch()`는 repository facade로 유지

테스트:

- v2 JSON parsing
- `REGULAR` only
- 영어 locale fallback
- 여러 `REGULAR` section의 메뉴 순서 유지
- `data: []` 처리
- stale cache면 `null`
- corrupt cache면 `null`

### Phase 4: `/v2/info` 운영시간 반영 (필수)

목표:

- Android 위젯 운영시간을 하드코딩이 아니라 `/v2/info` 기반으로 계산해 Flutter 앱과의 운영상태 drift를 없앤다.
- 하드코딩 운영시간 table을 완전히 제거하고, `/v2/info` cache를 유일한 운영시간 source로 삼는다.
- `info.json` cache가 없거나 손상되면 고정 운영시간이나 고정 끼니 경계로 대체하지 않고 위젯 데이터 오류를 표시한다. 메뉴 cache(`meal.json`)만 없거나 손상된 경우에는 `info.json`으로 계산한 현재 끼니의 빈 메뉴 상태를 렌더링한다.

전제:

- Phase 2에서 `BapUWidgetOperatingHours`가 이미 운영시간 계산의 단일 진입점이어야 한다. Phase 4는 이 진입점의 **데이터 소스만** 하드코딩 table → `/v2/info` cache 전용으로 바꾸는 작업이다(하드코딩 제거). 진입점이 흩어져 있으면 이 phase의 수정 범위가 커지므로 Phase 2가 선행되어야 한다.

작업:

1. (Dart) `/v2/info` 응답 raw JSON을 native가 읽는 공유 캐시 위치(`sharedWidgetCacheDir()`)에 `info.json`으로 저장한다. write는 `meal.json`과 동일하게 temp-file + rename. 경로 resolver는 iOS 위젯 확장 절의 Seam 1을 따른다.
2. (Dart) `/v2/info` fetch와 raw cache write를 담당하는 작은 info refresh/cache service를 둔다. `HomePage`는 이 service를 통해 `AppInfo`를 받아 UI에 전달하고, background refresh도 같은 service를 호출해 `info.json`을 갱신한다. 운영시간이 표시용을 넘어 위젯 source가 되므로, foreground fetch와 background refresh 모두에서 같은 write 경로를 사용한다.
3. (Native) `BapUWidgetOperatingHours`에 `info.json` parser를 추가한다. `weekday`/`weekend` × cafeteria(`dormitory`/`student`/`faculty`) × meal(`breakfast`/`lunch`/`dinner`) 구조를 `OperatingPeriod` table로 만든다.
4. (Native) `BapUWidgetTime`에 KST 기준 weekday/weekend 판정을 추가한다. `period()`/`status()`/`allPeriodsForBoundaryScheduling()`이 오늘 기준 table을 선택하게 한다.
5. (Native) 하드코딩 운영시간 table(`operatingPeriod`의 `when` 블록)을 제거한다. cache miss/parse 실패 시 운영상태를 unknown으로 두고 status 표시를 생략한다.
6. `getOperatingStatus`, `operatingStatusDisplay`, `BapUWidgetScheduleManager`가 모두 같은 cache source를 사용하는지, unknown 상태를 일관되게 처리하는지 확인한다.
7. (Native) `BapUWidgetScheduleManager`가 자정(일→월 포함) 경계를 예약 대상에 포함하게 한다. 자정에 끼니가 조식으로 리셋되고 weekday/weekend table이 바뀌므로, 자정 이후에는 새 날짜의 table로 다음 경계를 다시 계산해야 한다.

주의:

- Android 위젯 프로세스는 Flutter와 별도로 실행되므로, cache 파일 위치와 write atomicity가 `meal.json`과 동일하게 지켜져야 한다.
- 위젯 할랄은 기숙사 운영시간을 공유한다는 기존 정책을 cache 매핑에서도 유지한다.
- `/v2/info` 스키마(`weekday`/`weekend`, cafeteria/meal key)는 Dart `AppInfo`/`OperatingHours` 모델과 동일한 계약이므로, 이 key들도 `BapUWidgetContract` drift 방어 대상에 포함한다.
- 현재 native 위젯은 weekday/weekend를 구분하지 않는다. Phase 4에서 weekend table 지원이 새로 추가된다.
- 네트워크 책임을 늘리지 않기 위해 native에서 `/v2/info`를 직접 fetch하지 않는다. cache write는 Dart만 담당한다(Phase 5의 갱신 아키텍처와 일치). cache가 아예 없거나 손상된 상태는 정상 입력으로 보고 운영상태 unknown을 반환한다.
- 하드코딩 table 제거로 `operatingPeriod`가 반환하던 고정값이 사라지므로, 이 값을 참조하던 `BapUWidgetScheduleManager.allPeriodsToday()` 등 모든 호출부가 cache source로 전환됐는지 확인한다.
- 운영시간 cache가 없으면 `BapUWidgetScheduleManager`는 운영 경계 예약을 만들 수 없다. 이때는 status 경계 예약을 생략하고, 다음 Dart cache refresh + widget render push를 기다린다. 필요하면 자정 1회 보수 예약만 남기되, 하드코딩 운영시간으로 경계를 추정하지 않는다.

테스트:

- `info.json` parsing: weekday/weekend × 3식당 × 끼니
- KST 요일에 따라 weekday/weekend table 선택이 맞는지
- cache miss → 운영상태 unknown(표시 생략)
- corrupt cache → 운영상태 unknown(표시 생략)
- status 계산(운영 전/open/closing soon/closed)이 cache 기반 period로도 동일하게 동작

### Phase 5: 갱신 경로 단일화 — cache-only widget render (필수)

목표:

- 위젯 갱신을 성격에 따라 둘로 나누고, native network path를 제거한다.
  - **표시 갱신**(시간 경과에 따른 끼니/운영상태 전환): 순수하게 현재 시각 + cache된 운영시간의 함수이므로 네트워크 없이 `BapUWidgetScheduleManager`의 AlarmManager 경계 예약만으로 처리한다.
  - **데이터 갱신**(새 메뉴/운영시간 fetch): Dart가 단일 소유자다. Dart foreground/background refresh가 `meal.json`/`info.json` cache를 갱신한 뒤 native 위젯 재렌더를 push한다.
- native `BapUWidgetUpdateWorker`의 15분 주기 WorkManager 등록을 제거한다. 위젯이 스스로 네트워크를 폴링하거나 cache를 쓰는 책임을 없앤다.
- `BapUWidgetFetcher.fetch()`는 cache-only facade가 된다. cache가 없거나 오래됐거나 깨져 있으면 `null`을 반환하고, provider는 빈/오류 상태를 렌더한다.

근거:

- status 전환은 AlarmManager의 inexact 경계 예약으로 처리하므로, 15분 주기 WorkManager는 표시 목적에서 redundant다. 절전 정책에 따른 지연은 허용한다.
- 메뉴/운영시간 fetch는 Dart 백그라운드 refresh가 이미 담당하고 있으므로, native가 같은 데이터를 중복 폴링할 이유가 없다.
- cache write를 Dart로 일원화하면 `meal.json`/`info.json`의 스키마와 freshness 정책을 Flutter 앱과 위젯이 같은 소스로 공유한다.

작업:

1. `BapUWidgetUpdateWorker.schedule()`/`cancel()`(`enqueueUniquePeriodicWork()` 기반 15분 주기)과 `enqueueOneTime()`을 포함한 WorkManager 진입점을 모두 제거한다. 현재 `MainActivity`의 `refresh` handler가 부르는 것은 periodic이 아니라 `enqueueOneTime()`이므로, 이 호출도 `BapUWidgetUpdateDispatcher.renderAllWidgets`로 교체된다.
2. `BapUWidgetUpdateWorker.doWork()`에 의존하던 render 책임은 `BapUWidgetUpdateDispatcher.renderAllWidgets(context)`로 옮긴다. 이 함수는 `BapUWidgetFetcher.fetch(context)`를 호출하되, fetcher는 cache-only다.
3. 기존 `updateAllWidgets()`/`hasAnyWidget()` 책임도 `BapUWidgetUpdateDispatcher`로 옮긴다. WorkManager class는 남기지 않는다.
4. `BapUBaseWidgetProvider.onEnabled`는 periodic worker를 등록하지 않고 `BapUWidgetScheduleManager.scheduleNext(context)`만 호출한다.
5. `BapUBaseWidgetProvider.onDisabled`, boot receiver, scheduled receiver, config activity, MethodChannel handler가 모두 `BapUWidgetUpdateDispatcher`를 사용하게 한다.
6. `BapUBaseWidgetProvider.onUpdate`/`onAppWidgetOptionsChanged`는 network fetch 없이 cache read 기반 렌더로 정리한다.
7. Dart `meal_background_refresh_io.dart`에서 `MealRefreshService().refreshMealData()`가 성공한 직후 render 트리거(`updateHomeWidgets()` → iOS 대비를 위해 `refreshWidgets()` seam으로 일반화, Seam 2 참조)를 호출한다. Phase 4 이후에는 같은 background refresh에서 `/v2/info` cache도 갱신한 뒤 한 번만 호출한다.
8. 현재 `MainActivity`에 묶인 MethodChannel handler는 foreground Activity가 있을 때만 안전하다. background isolate에서도 호출되어야 하므로 application context 기반 native bridge로 옮긴다. 구현 방법은 Flutter plugin 또는 engine 등록 시점의 app-context channel 중 하나로 정하되, handler는 Activity에 의존하지 않고 `BapUWidgetUpdateDispatcher.renderAllWidgets(context)`만 호출한다.
9. AlarmManager의 inexact 경계 예약(자정·끼니 경계·운영 시작·마감 임박 시작·운영 종료)은 유지한다. 끼니 경계는 `info.json`에서 오늘 모든 식당의 breakfast/lunch 중 가장 늦은 종료 시각을 계산하고, 그 다음 분을 예약해 조식/중식/석식 선택을 전환한다. `info.json`이 없거나 불완전하면 고정 경계로 대체하지 않고 위젯 데이터 오류를 표시한다.
10. 운영시간 cache가 없으면 운영 경계 예약은 생략하지만, 자정과 끼니 경계 예약은 운영시간 cache와 무관하게 유지한다. 이 두 경계는 `MealTimeConfig`/`BapUWidgetTime` 계약만으로 계산 가능하다.
11. Dart background entrypoint에서는 `WidgetsFlutterBinding.ensureInitialized()` 이후 `DartPluginRegistrant.ensureInitialized()`를 호출해 `path_provider`, native render bridge 등 plugin/channel 등록을 보장한다.
12. `updateHomeWidgets()` 또는 새 native render bridge는 background refresh 경로에서 실패를 삼키지 않는다. foreground UI 호출에서는 log-only가 가능하지만, background task에서는 실패를 throw/return해서 Workmanager가 실패를 감지할 수 있어야 한다.

구현 시 주석으로 남길 것:

- WorkManager를 제거해도, 순수 native 안전망이 필요하면 provider XML의 `android:updatePeriodMillis`(최소 30분, 권한·코드 불필요, Doze 친화적이지만 coarse)로 주기 갱신을 붙일 수 있다는 대안을 provider 또는 XML 근처 주석에 남긴다. 기본 설계는 이 방식을 쓰지 않지만, Dart push 경로가 불안정하다고 판명될 때의 후속 검토 후보로 기록해 둔다.

주의:

- Dart 백그라운드 refresh가 실제로 등록·동작하고, refresh 성공 후 native render bridge가 호출되는지 먼저 확인해야 한다. 이것이 데이터 갱신 후 위젯 재렌더의 유일한 경로가 된다.
- native render push는 "새 데이터가 있으니 다시 그려라" 신호일 뿐이다. 데이터 자체는 항상 `meal.json`/`info.json` cache에서 읽는다.
- background isolate에서 `MainActivity` MethodChannel을 그대로 사용할 수 있다고 가정하지 않는다. Phase 5 구현 전 `updateHomeWidgets()`가 background task 안에서 실제 native handler까지 도달하는지 테스트하거나, app-context bridge로 먼저 옮긴다.
- background refresh 안에서는 plugin/channel 미등록, native handler 실패, cache path 접근 실패가 task 실패로 드러나야 한다. 실패를 debug log로만 삼키면 Workmanager는 성공으로 판단하고 위젯은 갱신되지 않는다.
- native에서 `/v2/menu` 또는 `/v2/info`를 직접 fetch하는 fallback은 남기지 않는다.

Phase 5까지가 필수 범위다. Phase 1-3(구조·테스트성), Phase 4(운영시간 데이터 정합성), Phase 5(갱신 경로 단일화)는 성격이 다르지만 모두 필수다.

## 후속 작업

### Follow-up 1: RemoteViews layout helper 정리

필수 범위(Phase 1-5) 이후에도 `BapUWidgetDataHelper.kt`가 너무 크다면 layout metrics와 fitting helper를 분리한다.

이 작업은 실제 기기 검증이 필수다.

확인 대상:

- 2x2
- 4x2 dual
- 4x2 status
- 4x4
- 긴 메뉴
- 영어 locale
- resize 후 표시

### Follow-up 2: Panel binder 공통화

Provider 반복 제거가 필요하면 panel binder를 추가한다.

단, provider 전체를 generic renderer로 합치지 않는다. 각 provider는 layout별 view id를 명시적으로 유지하고, panel 하나를 그리는 반복만 공통화한다.

### Follow-up 3: Update coordinator로 진입점 정리

Phase 5에서 native periodic WorkManager를 제거하고 갱신 경로(표시=AlarmManager, 데이터=Dart push)를 확정한 뒤에도, 남은 진입점(`onUpdate`, `onAppWidgetOptionsChanged`, scheduled receiver, config activity, MethodChannel, boot receiver)이 여러 개다. 이들을 하나의 coordinator로 모아 "전체 위젯 즉시 렌더"와 "다음 경계 예약"을 단일 경로로 만든다.

이 작업은 Phase 5의 갱신 정책 결정에 의존하므로 그 이후에 다룬다. Phase 5에서 이미 결정된 사항(native periodic WorkManager 제거, native network fallback 제거)은 여기서 다시 논의하지 않는다.

> `/v2/info` 운영시간 cache 연동은 필수 **Phase 4**로, native periodic WorkManager 제거와 cache-only 갱신 경로 단일화는 필수 **Phase 5**로 승격되어 이 절에서 제외했다.

## iOS 위젯 확장 대비 (Dart 저장/렌더 seam)

향후 iOS 홈 화면 위젯(WidgetKit)을 추가할 것을 전제로, Dart 파이프라인은 지금부터 플랫폼 의존 지점을 두 개의 seam으로 격리한다. 이 계획에서는 `home_widget` 패키지를 저장 계층으로 도입하지 않는다. raw JSON **파일**(`meal.json`/`info.json`) 계약과 native parser가 파일을 직접 읽는 구조를 유지해 Android/iOS 위젯을 같은 cache-only 모델로 맞추기 위해서다. `home_widget`은 reload trigger 같은 일부 용도로는 쓸 수 있지만, 저장소를 UserDefaults와 파일 cache로 이원화하지 않는 것이 이 계획의 기준이다.

### 왜 저장 위치만 문제인가

- Android: 위젯은 앱과 같은 sandbox의 `filesDir`(= `getApplicationSupportDirectory()`)를 그대로 공유한다.
- iOS: 위젯은 별도 extension 타깃/컨테이너에서 실행되어 앱의 `Library/Application Support`를 읽을 수 없다. **App Group 공유 컨테이너**(`group.pro.hexa.meal…`)에 써야만 위젯이 읽는다.

`MealCache`/`InfoCache`, `MealRefreshService`, background refresh, raw JSON 파일 계약은 모두 플랫폼 무관하게 재사용된다. 플랫폼에 따라 달라지는 것은 (1) 공유 캐시 디렉터리, (2) render 트리거 **둘뿐이다.**

### Seam 1: 공유 캐시 디렉터리 resolver

새 파일: `lib/core/widget_shared_storage.dart` (storage와 동일한 conditional export io/web 분기 방식)

```dart
Future<Directory> sharedWidgetCacheDir();
// Android: getApplicationSupportDirectory()  // == filesDir, 이미 위젯과 공유됨
// iOS:     App Group 컨테이너 경로 (MethodChannel로 조회)
```

- `storage_io.dart` 전체를 App Group 경로로 돌리지 않는다. 범용 앱 파일 저장소는 기존 `getApplicationSupportDirectory()`를 유지한다.
- 공유 캐시 디렉터리는 raw meal/info cache 파일(`meal.json`/`info.json`)에만 적용한다. `MealCache`/`InfoCache`가 공유-cache 전용 writer/reader를 주입받아 `sharedWidgetCacheDir()`를 사용하게 한다.
- 현재 `MealCache`는 writer/reader/lastModified reader를 생성자에서 주입받을 수 있으므로, `MealRefreshService`/`InfoCache` 생성 지점에서 공유-cache 전용 함수를 명시 주입한다. 범용 `storage_io.dart` 소비자와 기본 앱 파일 저장소를 함께 이동시키지 않는다.
- iOS App Group 경로는 Swift `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)?.path`를 반환하는 작은 native bridge로 얻는다. 이 bridge는 AppDelegate/root view controller에만 붙는 foreground channel이 아니라, background engine에도 등록되는 FlutterPlugin/app-context bridge여야 한다.
- Dart는 App Group ID를 하드코딩하지 않는다. Dart는 "공유 캐시 디렉터리"만 요청하고, native bridge가 group id를 알고 경로만 반환한다.
- App Group ID는 앱 타깃, 위젯 extension 타깃, Swift bridge가 모두 같은 값을 써야 하므로 `.xcconfig` 또는 build setting에서 단일화한다.
- Android는 지금과 동일하게 `getApplicationSupportDirectory()`를 반환하므로 동작 변화가 없다.

### Seam 2: render 트리거

`features/widget/widget_service.dart`의 Android 전용 `updateHomeWidgets()`를 플랫폼 무관 `refreshWidgets()`로 일반화한다.

- Android: 기존 채널 → `BapUWidgetUpdateDispatcher.renderAllWidgets`
- iOS: 채널 → `WidgetCenter.shared.reloadAllTimelines()`

Phase 5의 background refresh 성공 후 호출부는 `refreshWidgets()`만 부르면 되고 플랫폼 분기를 알 필요가 없다. `Platform.isAndroid` 가드는 seam 내부로 들어간다.

iOS render trigger도 foreground `AppDelegate`/root view controller에만 묶인 channel이면 부족하다. BGTask/headless background engine에서 `WidgetCenter.shared.reloadAllTimelines()`까지 도달해야 하므로, Seam 1과 같은 app-context FlutterPlugin bridge로 등록한다.

### 캐시 경로 불변식 (플랫폼별)

cache-only 위젯의 핵심 불변식(경로 일치)은 플랫폼별로 일반화된다. 어느 쪽이든 어긋나면 native network fetch가 없으므로 위젯이 데이터 오류 또는 빈 메뉴 상태에 머문다.

- Android: Dart `getApplicationSupportDirectory()/meal.json` == native `context.filesDir/meal.json`
- iOS: Dart App Group 컨테이너/`meal.json` == 위젯 extension이 **같은 group id로 여는** 컨테이너/`meal.json`

두 경우 모두 write→read 회귀 테스트로 검증한다(테스트 전략의 “cache 파일 경로 일치” 참조).

### iOS 갱신 모델: AlarmManager 대신 TimelineProvider

Android는 `AlarmManager`로 자정, 끼니 경계, 운영시간 경계를 직접 깨워 위젯을 다시 렌더한다. iOS WidgetKit은 이 모델이 아니다. `TimelineProvider`가 여러 timeline entry를 미리 제공하고, 시스템이 그 entry 시각에 맞춰 위젯 표시를 전환한다.

iOS cache-only 위젯을 구현할 때는 timeline entry에 최소한 다음 경계를 포함한다.

- 자정
- 끼니 경계: `info.json`에서 계산한 breakfast/lunch 최종 종료 + 1분
- 운영 시작
- 마감 임박 시작
- 운영 종료

`refreshWidgets()`의 iOS 구현(`WidgetCenter.shared.reloadAllTimelines()`)은 timeline을 다시 요청하게 만드는 trigger일 뿐이다. 실제 표시 전환 타이밍은 reload 호출 자체가 아니라 `TimelineProvider`가 제공한 timeline entry들이 좌우한다.

Android와 iOS 모두 분 단위 카운트다운 없이 coarse 상태(open/마감임박/종료)를 표현한다.

### iOS 구현 시 주의 (나중 작업)

- App Group entitlement를 앱 타깃과 위젯 extension 타깃 **양쪽에** 설정한다(Xcode, Dart 무관).
- iOS 위젯 TimelineProvider도 cache-only로 유지한다(네트워크 없음, App Group 파일만 읽음). Android의 cache-only 결정과 동일하다.
- iOS BGAppRefresh는 Android WorkManager보다 덜/불규칙하게 실행된다. workmanager 플러그인의 iOS BGTaskScheduler로 `MealRefreshService`를 재사용하되, 주 갱신 경로는 앱 foreground 진입이고 BG는 보조다.
- `sharedWidgetCacheDir()`가 iOS에서 App Group 조회에 실패하면(entitlement 누락 등) cache write/read가 실패한다. 이 실패는 Phase 5의 background 실패 전파 정책과 동일하게 삼키지 않는다.
- `getApplicationSupportDirectory()`에서 App Group container로 cache 위치가 바뀌면 기존 iOS 앱 sandbox의 예전 `meal.json`/`info.json`은 읽지 않는다. 이 파일들은 재생성 가능한 cache이므로 migration하지 않고 cache miss로 처리해 다음 refresh에서 다시 채운다.

## 테스트 전략

### Kotlin unit test

필수 테스트:

- `BapUWidgetTimeTest`
  - 끼니 경계
  - KST week id
  - day api key
- `BapUWidgetOperatingHoursTest`
  - 식당/끼니별 운영시간
  - 운영 전/open/closing soon/closed
  - dorm halal은 dormitory 운영시간 공유
- `BapUWidgetMealParserTest`
  - v2 JSON parsing
  - `REGULAR` only
  - 영어 locale fallback
  - 여러 `REGULAR` section의 메뉴 순서 유지
  - `data: []`

선택 테스트:

- repository cache freshness
- corrupt cache -> `null`
- stale cache -> `null`

repository 테스트는 fake file boundary를 만들기 전까지는 과도하게 붙이지 않는다. native HTTP boundary는 최종 구조에 없으므로 테스트하지 않는다.

### Dart/Kotlin drift 방어

완전한 cross-language import는 어렵다. 대신 같은 의미의 fixture를 양쪽 테스트에 둔다.

검증할 항목:

- 끼니 경계: `info.json`에서 계산한 breakfast/lunch 최종 종료 시각과 그 다음 분
- KST week id 경계
- API enum key
- `REGULAR` only 정책
- 영어 메뉴 fallback
- **cache 파일 경로 일치**: Dart가 쓰는 공유 캐시 위치와 native/위젯이 읽는 위치가 실제로 같은 파일인지(`meal.json`/`info.json`). 플랫폼별로 — Android는 Dart `getApplicationSupportDirectory()` == native `context.filesDir`, iOS는 Dart App Group 컨테이너 == 위젯 extension이 같은 group id로 여는 컨테이너(iOS 위젯 확장 절 Seam 1). 값 대조가 아니라 write→read 확인이 필요하므로 integration/instrumented test로, Dart가 쓴 파일을 native(위젯) 경로에서 읽어 검증한다. cache-only에서는 이 경로가 어긋나면 native network fetch 없이 위젯이 데이터 오류 또는 빈 메뉴 상태에 머무르므로 필수 회귀 테스트다.
- **iOS App Group ID 일치**: 앱 타깃, 위젯 extension 타깃, Swift bridge가 같은 App Group ID를 사용한다. Dart에는 group id를 하드코딩하지 않고, native bridge가 반환한 경로만 사용한다.

### 실제 기기 검증

RemoteViews와 launcher rendering은 unit test로 충분히 검증할 수 없다. 다음 변경이 있을 때는 실제 기기 또는 emulator 검증이 필요하다.

- `truncateMenuByRealLayout` 변경
- XML dimension 변경
- panel binder 도입
- provider updateWidget 구조 변경
- status 표시 방식 변경

### Background refresh 검증

Phase 5에서는 Dart background refresh가 데이터 갱신의 유일한 owner가 되므로 다음 경로를 별도로 검증한다.

- `meal_background_refresh_io.dart`의 Workmanager task가 `MealRefreshService().refreshMealData()` 성공 후 native render bridge를 호출한다.
- Phase 4 이후 같은 task가 `/v2/info` cache도 갱신한 뒤 native render bridge를 한 번만 호출한다.
- background entrypoint가 `DartPluginRegistrant.ensureInitialized()`를 호출해 cache path와 native bridge plugin/channel을 사용할 수 있다.
- background isolate에서 `updateHomeWidgets()`가 `MainActivity` 없이도 native handler에 도달한다.
- iOS BGTask/headless isolate에서 App Group path 조회와 `WidgetCenter.shared.reloadAllTimelines()` 호출이 foreground view controller 없이 native bridge에 도달한다.
- background refresh 경로에서 native render bridge 실패가 log-only로 삼켜지지 않고 task 실패로 관찰된다.
- native handler는 네트워크를 호출하지 않고 `BapUWidgetUpdateDispatcher.renderAllWidgets(context)`만 호출한다.
- cache miss/stale/corrupt 상태에서도 위젯 렌더가 crash 없이 빈/unknown 상태로 끝난다.

### iOS WidgetKit 검증

iOS 위젯 구현 시 추가로 확인한다.

- `TimelineProvider`가 App Group의 `meal.json`/`info.json`만 읽고 네트워크를 호출하지 않는다.
- timeline entry가 최소 자정, `info.json`에서 계산한 끼니 전환 경계, 운영 시작, 마감 임박 시작, 운영 종료를 포함한다.
- App Group 조회 실패 또는 cache miss/corrupt 시 위젯이 crash하지 않고 empty/unknown 상태를 표시한다.
- 기존 앱 sandbox `Application Support`에 남아 있는 예전 cache가 없어도 다음 foreground/background refresh로 App Group cache가 재생성된다.

## 구현 시 주의할 점

### 기존 저장값 호환

식당 설정은 이미 `0`, `1`, `2`, `10`으로 저장된다. enum을 도입해도 SharedPreferences 저장값은 그대로 유지한다.

### RemoteViews 제약

Android widget은 일반 View binding과 다르다. 현재 실측 기반 fitting 로직은 launcher별 크기 오차를 보수적으로 처리하기 위한 코드다. 단순 line count 방식으로 되돌리거나, 검증 없이 파일만 이동하지 않는다.

### 과도한 추상화 금지

현재 필수 목표는 15개 파일 구조가 아니다. Phase 1-5의 결과로 새로 필요한 native 파일은 대략 6개다.

- `BapUWidgetContract.kt`
- `BapUWidgetTime.kt`
- `BapUWidgetOperatingHours.kt`
- `BapUWidgetMealParser.kt`
- `BapUWidgetMealRepository.kt`
- `BapUWidgetUpdateDispatcher.kt`

Phase 4는 새 native 파일 없이 `info.json` parsing을 `BapUWidgetOperatingHours.kt`에 포함하고, Dart 쪽에 `info.json` cache write만 추가한다(커지면 `BapUWidgetInfoParser.kt`로 분리). 그 외 분리는 실제 중복이 계속 비용을 만들 때만 한다.

## 권장 우선순위

1. Phase 0: Android unit test harness 확립
2. Phase 1: contract + enum 도입
3. Phase 2: time + operating hours 분리
4. Phase 3: parser + repository 정리
5. Phase 4: `/v2/info` 운영시간 반영 + 하드코딩 table 제거
6. Phase 5: 갱신 경로 단일화 + native periodic WorkManager 제거 + native network fallback 제거
7. Follow-up: provider/layout/update coordinator 정리

필수 범위는 Phase 5에서 끊는다. 이후 작업은 별도 이슈로 다룬다.

## 완료 기준

Phase 0-5 완료 기준:

- `:app:testDebugUnitTest`가 실행 가능하고 통과한다.
- cache file, API enum, KST/time boundary 상수가 `BapUWidgetContract.kt` 중심으로 모여 있다.
- 식당/끼니 계산 로직이 raw `Int` 대신 enum을 중심으로 동작한다.
- 현재 끼니, KST week id, 운영상태 계산이 unit test로 검증된다.
- `/v2/menu` parser가 Android framework 없이 unit test 가능하다.
- `BapUWidgetFetcher.fetch(context)` facade는 유지하되 nullable `Context? = null` 기본값은 제거되어 모든 호출부가 명시적인 `Context`로 cache-only read를 수행한다.
- native widget contract/fetcher/repository에 `/v2/menu` endpoint URL 상수가 남아 있지 않다.
- 하드코딩 운영시간 table이 코드에서 제거되고, 위젯 운영상태가 `/v2/info` cache만으로 계산된다.
- cache 부재 시 운영상태 표시가 생략되며, 잘못된 운영상태가 표시되지 않는다.
- native `BapUWidgetUpdateWorker`(15분 주기 WorkManager)가 제거되고, 데이터 갱신은 Dart cache write + background-safe native render push, 표시 갱신은 AlarmManager 경계 예약으로 분리되어 있다.
- AlarmManager 표시 갱신은 자정, `info.json` 기반 끼니 경계, 운영 시작, 마감 임박 시작, 운영 종료 이후 상태 전환을 포함한다.
- native widget 코드에 `/v2/menu` 또는 `/v2/info` HTTP fallback 경로가 남아 있지 않다.
- Dart write 경로와 native read 경로 일치(`meal.json`/`info.json`)가 테스트로 검증된다. cache-only에서 이 경로가 어긋나면 위젯이 영구 blank가 되므로 회귀 방지 테스트가 있어야 한다.
- Dart background refresh가 `DartPluginRegistrant.ensureInitialized()` 이후 `meal.json`/`info.json` cache write 성공 후 native 위젯 렌더를 호출한다.
- background refresh 경로에서 native render bridge 실패가 Workmanager task 실패로 전파된다.
- Dart 저장/렌더 seam은 Android 동작을 유지하면서 iOS App Group/WidgetKit 구현으로 확장 가능한 형태다. raw meal/info cache만 공유 캐시 디렉터리를 사용하고, 범용 앱 파일 저장소는 불필요하게 App Group으로 이동하지 않는다.
- iOS 대비 설계에서 Dart는 App Group ID를 하드코딩하지 않고, native bridge는 background engine에서도 App Group path 조회와 WidgetKit timeline reload를 처리할 수 있어야 한다.
- provider XML/코드 근처에 `updatePeriodMillis` 대안이 주석으로 기록되어 있다.
- `flutter build apk`가 통과한다.

전체 후속 작업 완료 기준:

- provider 파일은 layout/view id 선택과 최종 `updateAppWidget` 호출 중심으로 얇아져 있다.
- 모든 update 진입점은 하나의 coordinator를 통한다.
- 실제 기기에서 4개 위젯 크기 모두가 정상 표시된다.
