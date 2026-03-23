# BapU 아키텍처 분석

> `meal_client` 코드베이스에 대한 소프트웨어 엔지니어링 관점의 분석.
> 작성일: 2026-03-17. 코드는 수정하지 않으며, 읽기 전용 분석 문서입니다.

---

## 1. 계층 구조 개요

이 프로젝트는 느슨하게 구분된 세 계층으로 구성되어 있습니다. 명시적인 아키텍처 경계(리포지터리 패턴, 유스케이스 계층 등)는 없지만, 소규모 앱으로서의 관심사 분리는 합리적인 수준입니다.

```
┌─────────────────────────────────────────────────────┐
│  UI 계층                                            │
│  pages/home/home_page.dart                          │
│  pages/home/home_app_bar.dart                       │
│  pages/home/week_meal_view.dart                     │
│  pages/home/meal_card.dart                          │
│  pages/home/nested_page_scroll.dart                 │
│  pages/home_drawer.dart                             │
├─────────────────────────────────────────────────────┤
│  상태 / 도메인 계층                                  │
│  model.dart           — BapUModel (전역 상태)       │
│  meal.dart            — 도메인 데이터 클래스         │
│  string.dart / i18n.dart — 다국어 기본 요소          │
├─────────────────────────────────────────────────────┤
│  데이터 / 인프라 계층                                │
│  api_v2.dart          — HTTP + JSON 파싱            │
│  data.dart            — 캐시 오케스트레이션          │
│  storage.dart (+ _io / _web) — 파일 I/O             │
│  platform_http_client.dart (+ _io / _web) — HTTP    │
└─────────────────────────────────────────────────────┘
```

`home_page.dart`가 도메인 계층을 거치지 않고 `api_v2.dart`와 `data.dart`를 직접 임포트하고 있습니다. 데이터 접근과 UI를 분리해 줄 리포지터리나 서비스 객체가 없습니다.

---

## 2. 테마 / 다크 모드

### 현재 구현 방식

`BapUModel`이 `Brightness _themeBrightness`를 보관합니다. 루트(`MyApp.build`)에 위치한 `Consumer<BapUModel>`은 밝기가 바뀔 때마다 `ThemeData`와 `ColorScheme`을 포함한 `MaterialApp` 전체를 다시 빌드합니다. 플랫폼 밝기는 `main()` 내부의 Provider `create:` 콜백에 등록된 콜백으로 전달됩니다.

```dart
// main.dart — Provider 팩토리 안에 플랫폼 사이드 이펙트 등록
platformDispatcher.onPlatformBrightnessChanged = () {
  model.setThemeBrightness(platformDispatcher.platformBrightness);
};
```

### 문제점

**a. 비관용적(non-idiomatic) 테마 패턴.**
Flutter의 `MaterialApp`에는 이 목적을 위해 설계된 `themeMode`와 `darkTheme` 파라미터가 있습니다. 표준 패턴:

```dart
MaterialApp(
  themeMode: ThemeMode.system,  // 시스템 설정 자동 반영
  theme: lightThemeData,
  darkTheme: darkThemeData,
)
```

이 패턴에서는 Flutter가 `MaterialApp`을 다시 빌드하지 않고 내부적으로 테마를 교체합니다. 현재 방식은 밝기가 바뀔 때마다 `MaterialApp`(및 그 하위 트리 전체)를 다시 빌드합니다.

**b. Provider `create:` 콜백 안의 사이드 이펙트.**
`create:` 파라미터는 팩토리 함수로, 모델 객체를 생성하는 역할입니다. `PlatformDispatcher` 콜백을 그 안에 등록하는 것은 호출 지점에서는 보이지 않는 사이드 이펙트이며, 초기화 순서를 암묵적으로 만듭니다. `onPlatformBrightnessChanged`와 같은 콜백은 객체 생성 시점이 아닌, `initState`와 같은 라이프사이클 메서드에 속합니다.

**c. `BapUModel`이 관련 없는 두 관심사를 혼합.**
언어 설정과 테마 밝기는 독립적인 앱 수준 설정입니다. 현재는 하나의 `ChangeNotifier`에 결합되어 있어, 밝기 변경이 언어 변경 리스너를 트리거하고 반대도 마찬가지입니다. `notifyListeners()`가 세분화되지 않아 모든 `Consumer<BapUModel>` 위젯이 어느 한 필드의 변경에도 다시 빌드됩니다.

**d. 매 빌드마다 수동 `ColorScheme.copyWith` 오버라이드.**
`surface`와 `surfaceContainer`가 `MaterialApp` 빌드마다 하드코딩된 `Color.fromARGB` 리터럴로 오버라이드됩니다. 이는 고정된 디자인 결정이 동적 계산인 척 위장된 것입니다.

---

## 3. 국제화 / 다국어 지원

### 현재 구현 방식

커스텀 `MultiLanguageString` 클래스가 `eng`와 `kor` 필드를 보유합니다. 모든 호출 지점에서 `Language` 값을 전달하고 `.getLocalizedString(language)`를 수동으로 호출합니다. `Language` 열거형은 파라미터로 위젯 트리를 통해 명시적으로 전달됩니다. `main.dart`의 언어 감지는 영구적으로 비활성화되어 있습니다:

```dart
if ( /* platformDispatcher.locale.languageCode == "ko" */ true) {
  language = Language.kor;
}
```

이 비활성화된 조건은 `main.dart`에 두 번 등장합니다(21번째 줄과 39번째 줄).

### 문제점

**a. 언어 전환이 완전히 비활성화됨.**
`onLocaleChanged` 콜백이 연결되어 있고 `BapUModel.changeLanguage`도 구현되어 있지만, 감지 조건이 주석 처리되고 `true`로 대체되어 있습니다. 인프라는 존재하지만 영구적으로 단락되어 있어, 미래 개발자가 주석 처리된 조건을 발견하지 못할 수 있습니다.

**b. 비관용적 현지화 방식.**
Flutter의 표준 접근법(`flutter_localizations` + `intl` + `.arb` 파일)은 다음을 제공합니다:
- 컴파일 타임 키 안전성
- 복수형 및 성별 규칙
- `intl`을 통한 날짜/숫자/통화 포맷
- `Localizations.of(context)`를 통한 올바른 로케일 상속
- 툴링 지원 (추출, 번역 워크플로우)

현재의 `MultiLanguageString` 패턴은 현지화된 문자열이 필요한 모든 위젯이 `Language` 파라미터를 받아야 하므로, 위젯 인터페이스를 현지화 메커니즘에 결합시킵니다. 세 번째 언어를 추가하려면 모든 `MultiLanguageString` 정의를 수정해야 합니다.

**c. `language`가 위젯 트리를 통해 수동으로 전달됨.**
`WeekMealTabBarView`, `DayOfWeekTabBar`, `AnimatedDateTitle`, `_OperationHoursSection`, `HomePageDrawer`가 모두 `Language`를 생성자 파라미터로 받습니다. 이는 프롭 드릴링(prop-drilling)과 동일합니다. Flutter의 표준 대안은 `Localizations.of(context)` 또는 전용 `Consumer`/`context.read`입니다.

**d. `string.dart`에서 날짜 포맷이 직접 구현됨.**
`getLocalizedDate()`는 `intl`의 `DateFormat`이 한 줄로 처리하는 것을 30줄의 switch문으로 재구현한 것입니다. 월 이름이 `MultiLanguageString` 상수로 하드코딩되어 있어, 언어 목록이 확장되면 한국어의 연-월-일 순서 등 로케일 특화 날짜 순서를 올바르게 처리하지 못합니다.

**e. `string.dart`가 데이터와 로직을 혼합.**
문자열 상수와 `getLocalizedDate()` 함수가 같은 파일에 있습니다. 이 함수는 문자열 상수가 아닌 날짜 포맷 유틸리티로, 별도의 유틸리티 또는 도메인 계층에 속합니다.

---

## 4. 상태 관리

### 현재 구현 방식

`BapUModel`(전역, Provider `ChangeNotifier`)이 언어와 밝기를 보관합니다. `HomePageModel`(로컬, 일반 가변 클래스)이 현재 `MealOfDay`와 `DayOfWeek`를 보관합니다. `_HomePageState`가 `HomePageModel`을 소유하고 `setState()`를 통해 변경합니다.

### 문제점

**a. `HomePageModel`이 불변(immutable)도 아니고 `ChangeNotifier`도 아님.**
필드가 직접 할당되는 일반 가변 클래스입니다. 모든 변경은 `_HomePageState` 수준의 `setState()`로 감쌉니다. 이 패턴은 동작하지만 의미적으로 불명확합니다: `HomePageModel`은 데이터 홀더처럼 보이지만 상태 객체로 동작합니다. 단순 불변 레코드(필드를 `_HomePageState`로 직접 이동)이거나 적절한 `ChangeNotifier`여야 합니다.

**b. 전환 가드 상태(`_isMealOfDayButtonTransition`)가 애드혹 플래그.**
이 불리언은 프로그래밍 방식의 페이지 애니메이션 중 `onPageChanged`가 버튼 상태를 덮어쓰는 것을 방지합니다. 근본적인 문제는 버튼으로 시작한 전환과 스와이프로 시작한 전환이 동일한 `onPageChanged` 콜백을 공유하면서 출처를 구분할 방법이 없다는 것입니다. 상태 머신(예: `_TransitionSource { none, button, swipe }` 열거형)이 더 명확할 것입니다.

**c. 생성 시점의 `BapUModel` 사이드 이펙트 (§2b 반복).**
`PlatformDispatcher` 콜백이 라이프사이클 메서드가 아닌 Provider `create:` 중에 설정됩니다. 이는 테스트나 모킹이 어려운 암묵적 초기화 형태입니다.

---

## 5. 도메인 / 데이터 모델

### 문제점

**a. 열거형 인덱스 데이터가 컬렉션 대신 명명된 필드를 사용.**
`WeekMeal`은 일곱 개의 명명된 필드(`mon`, `tue`, ..., `sun`)를 가집니다. `DayMeal`은 세 개(`breakfast`, `lunch`, `dinner`), `CafeteriaMeal`도 세 개(`dormitory`, `student`, `faculty`)를 가집니다. 접근은 `fromDayOfWeek()`, `fromMealOfDay()`, `fromCafeteria()`의 수동 switch문으로 이루어집니다.

`DayOfWeek`, `MealOfDay`, `Cafeteria`가 연속된 정수 인덱스를 가진 열거형이므로, 이 클래스들은 `enum.index`로 인덱싱된 `List<T>`나 Dart의 `EnumMap` 스타일 패턴을 사용할 수 있습니다. 현재 상태에서는 새 카페테리아를 추가하려면 `Cafeteria` 열거형과 모든 switch문을 함께 수정해야 합니다.

**b. `empty()` 생성자가 부분적으로 가변적인 객체를 반환.**
`CafeteriaMeal.empty()`는 `dormitory`, `student`, `faculty`를 `List.empty(growable: true)`로 초기화합니다. 필드의 `final` 키워드가 리스트 참조 재할당을 막지만, 리스트 내용은 가변적입니다. `api_v2.dart`의 `parseRawMeal()`이 이 리스트에 항목을 추가하여 모델을 구성합니다. 이는 모델이 구성 중에는 가변적이지만 이후에는 불변으로 다루어지는 암묵적인 2단계 초기화를 의미합니다.

더 깔끔한 설계는 중간 빌더 구조로 파싱한 뒤 한 번에 불변 모델 객체를 생성하는 것입니다.

**c. 상속이 타입 태그로 사용됨.**
`KoreanMeal`과 `HalalMeal`은 필드나 메서드를 추가하지 않고 `Meal`을 상속합니다. 유일한 목적은 호출 코드가 `case KoreanMeal _:` 패턴 매칭으로 식사 유형을 구분할 수 있게 하는 것입니다. Dart의 sealed class나 `Meal`의 열거형 필드(예: `MealType? type`)가 이 의도를 더 직접적으로 표현합니다.

**d. `nextMealOfDay()`와 `nextDayOfWeek()`가 최상위 함수.**
이들은 논리적으로 해당 열거형의 연산이므로 확장 메서드로 더 쉽게 발견될 수 있습니다:

```dart
extension MealOfDayExt on MealOfDay {
  MealOfDay get next { ... }
}
```

---

## 6. API / 네트워크 계층

### 문제점

**a. API 키가 한국어 텍스트.**
`parseRawMeal()`은 한국어 문자열 리터럴(`"기숙사 식당"`, `"학생 식당"`, `"교직원 식당"`)로 `meal["restaurantType"]`을 분기합니다. API가 한국어 표현을 변경하면 파싱이 조용히 `FormatException`을 던집니다. API 수준의 상수나 매핑 테이블이 더 견고할 것입니다.

**b. 전역 가변 HTTP 클라이언트.**
`_httpClient`가 `api_v2.dart`의 모듈 수준 `final`입니다. 전역 싱글톤으로, 의존성 주입 없이는 단위 테스트가 불가능합니다. 더 깔끔한 설계는 클라이언트를 파라미터로 받거나 Provider 트리를 통해 주입하는 것입니다.

**c. 타입이 없는 오류 처리.**
모든 네트워크 오류가 일반 `Exception("HTTP ...")`으로 던져집니다. `data.dart`의 호출자가 캐시 유효성 판단을 위해 모든 예외를 잡습니다. 타입화된 오류 클래스(`NetworkException`, `ParseException`, `CacheExpiredException`)가 오류 처리를 명시적으로 만들고 관련 없는 오류를 실수로 삼키는 것을 방지합니다.

**d. `parseRawMeal`이 출력을 변경하는 순수 함수인 척.**
`async` I/O가 없음에도 `parseRawMeal`은 `String`을 받아 `WeekMeal.empty()` 내부의 growable 리스트를 수정합니다. 순수 함수가 아닌데 숨겨진 변경이 있습니다. `parse*`라는 이름의 함수에서 이는 최소 놀람의 원칙을 위반합니다.

---

## 7. 캐시 계층 (`data.dart`)

### 문제점

**a. 캐시 무효화 로직에 미묘한 오프-바이-원.**
`_getKstWeekNumber`는 `(diff.inDays / 7).toInt() + 1`을 계산합니다. 부동소수점 나눗셈의 `toInt()` 내림과 UTC→KST 변환이 조합되면, DST나 일 미만 정밀도에 따라 동일한 순간에도 다른 주 번호가 나올 수 있습니다. ISO 8601 주 번호(`(date.difference(jan4).inDays / 7).floor() + 1`)를 사용하는 것이 더 표준적입니다.

**b. 캐시 전략이 필요 이상으로 광범위.**
캐시가 ISO 주 전체 동안 유효합니다. 메뉴 데이터는 날마다 바뀔 수 있습니다. `downloadedMeal` future가 캐시 로드 후 항상 최신 데이터를 가져오므로 부분적으로 완화되지만, 캐시 유효 기간이 의미론적으로 필요보다 넓습니다.

**c. `data.dart`가 I/O와 비즈니스 로직을 혼합.**
`fetchAndCacheMealData()`가 세 가지를 수행합니다: HTTP fetch, 파일 쓰기, 파싱. `getCachedMealData()`가 파일 타임스탬프 읽기, 주 번호 계산, 파일 읽기, 파싱을 수행합니다. 단일 책임 원칙에 따라 더 작은 함수로 분해될 수 있습니다.

---

## 8. UI 아키텍처

### 문제점

**a. UI와 데이터 계층 간 직접 결합.**
`home_page.dart`가 `api_v2.dart`와 `data.dart`를 직접 임포트합니다. 리포지터리나 서비스 객체가 페이지를 데이터 소스로부터 분리하여 데이터 계층을 독립적으로 테스트 가능하게 하고 페이지의 의존성을 명시적으로 만들 것입니다.

**b. `home_drawer.dart`가 `SharedPreferences`에 직접 접근.**
드로어 위젯이 캐시된 공지사항 텍스트를 가져오기 위해 `SharedPreferences`에서 직접 읽습니다. 이는 UI 위젯 내의 비즈니스 로직(영속성 접근)입니다. 공지사항 내용은 상태로 전달받거나 컨트롤러/모델이 로드해야 합니다.

**c. `initState`가 라이프사이클 가드 없이 비동기 작업 수행.**
`_HomePageState.initState`가 두 개의 awaited되지 않은 future를 실행합니다:
- `fetchRawAnnouncement().then(...)` — 콜백 내에서 `showDialog(context: context, ...)`를 호출합니다. future가 완료되기 전에 위젯이 dispose되면 오래된 `context`를 사용하게 됩니다. 버튼 핸들러에는 있는 `mounted` 확인이 여기에는 없습니다.
- `rootBundle.loadString(...).then(...)` — `LicenseRegistry.addLicense(...)`를 호출하는데, 이는 핫 리로드 시 누적되는 전역 사이드 이펙트입니다.

**d. 카페테리아 식별에 참조 동등성 사용.**
`week_meal_view.dart`에서 카페테리아 유형이 다음과 같이 결정됩니다:

```dart
if (meals == nowMeal.dormitory) { ... }
else if (meals == nowMeal.student) { ... }
else if (meals == nowMeal.faculty) { ... }
```

이는 `List<Meal>` 참조를 비교합니다. `CafeteriaMeal`의 동일한 리스트 객체가 직접 순회되기 때문에 동작하지만, 리스트를 복사하거나 변환하도록 리팩토링되면 식별 확인이 조용히 실패하여 모든 카페테리아 레이블이 빈 상태가 됩니다. `Cafeteria` 열거형이 이미 존재하므로 이를 사용해 어떤 카테고리에 속하는지 명시적으로 추적해야 합니다.

**e. 식사 카드 제목 구성이 잘못된 계층에 위치.**
카페테리아 카드 제목(예: "기숙사 식당 한식")을 구성하는 로직이 레이아웃 위젯인 `WeekMealTabBarView`에 있습니다. 제목 구성은 도메인 관심사로, 데이터 모델이나 프리젠터 계층에 더 가까이 있어야 합니다.

---

## 9. 커스텀 스크롤 시스템 (`nested_page_scroll.dart`)

스크롤 시스템은 코드베이스에서 가장 복잡한 부분이며 주석이 잘 작성되어 있습니다. 다음은 사소한 관찰 사항입니다:

**a. `NestedPageScrollControllerGroup`이 `ChangeNotifier`를 사용하지 않으면서 확장.**
클래스가 `ChangeNotifier`를 확장하지만 자신의 공개 메서드에서 `notifyListeners()`를 호출하지 않습니다. 개별 `NestedPageScrollController` 인스턴스가 호출합니다(`ScrollController`를 통해 `ChangeNotifier`이기도 하므로). 그룹 자체가 리슨되지 않는다면 `ChangeNotifier` 확장은 혼란을 야기합니다.

**b. `prevPage`가 `0`으로 초기화되고 재설정되지 않음.**
`_NestedPageScrollViewState.prevPage`가 필드 초기화 시 `0.0`으로 설정되고 `onVerticalDragStart`에서 업데이트됩니다. 드래그 세션 사이에는 마지막 드래그의 값을 유지하며 실제 현재 페이지 위치를 반영하지 않습니다. 사용자가 탭을 눌러 페이지를 이동한 후 드래그하면 `prevPage`가 `currentPage`보다 뒤처질 수 있습니다. `onVerticalDragUpdate`의 `middlePage` 교차 계산이 전환 타이밍에 이 값을 의존합니다.

**c. `_isAnimatingPage`가 `setState` 없이 변경됨.**
이는 의도적(리빌드 방지)이지만, 이 필드가 Flutter의 리빌드 사이클에 보이지 않음을 의미합니다. 이 의도적 생략에 대한 주석이 미래 유지보수자에게 도움이 될 것입니다.

---

## 10. 요약 표

| 영역 | 심각도 | 문제 |
|------|--------|------|
| 테마 | 중간 | 비관용적: `MaterialApp` 재빌드 대신 `themeMode` + `darkTheme` 사용 권장 |
| 테마 | 낮음 | `ColorScheme` surface 오버라이드가 빌드마다 하드코딩 |
| i18n | **높음** | 언어 감지 영구 비활성화 (`true`가 실제 조건 대체) |
| i18n | 중간 | `Localizations` 대신 `Language` 수동 프롭 드릴링 |
| i18n | 중간 | `intl` 대신 수동 날짜 포맷 구현 |
| i18n | 낮음 | `string.dart`가 문자열 상수와 포맷 로직 혼합 |
| 상태 | 낮음 | `HomePageModel`의 모호한 가변성; ChangeNotifier도 불변도 아님 |
| 상태 | 낮음 | `_isMealOfDayButtonTransition`이 애드혹 불리언; 열거형이 적합 |
| 상태 | 중간 | Provider `create:` 안의 사이드 이펙트 (`PlatformDispatcher` 콜백) |
| 데이터 모델 | 낮음 | 명명된 필드 + 수동 switch를 열거형 인덱스 리스트로 대체 가능 |
| 데이터 모델 | 중간 | `empty()` + append 패턴의 2단계 가변 생성 |
| 데이터 모델 | 낮음 | 타입 태그로 사용된 서브클래스 (`KoreanMeal`/`HalalMeal`) |
| 데이터 모델 | 낮음 | `nextMealOfDay`/`nextDayOfWeek`가 확장 메서드여야 함 |
| API | 중간 | 한국어 문자열 리터럴 API 키 (취약한 파싱) |
| API | 중간 | 모듈 수준 HTTP 클라이언트 (DI 없이 테스트 불가) |
| API | 낮음 | 모든 오류에 타입 없는 `Exception` |
| 캐시 | 낮음 | 주 번호 계산의 정밀도 엣지 케이스 가능성 |
| 캐시 | 낮음 | `data.dart` 단일 책임 원칙 위반 |
| UI | 중간 | `home_page.dart`가 `api_v2` / `data` 직접 임포트 (리포지터리 계층 없음) |
| UI | 중간 | `home_drawer.dart`가 `SharedPreferences`에 직접 접근 |
| UI | 중간 | `initState` async future에 `mounted` 확인 누락 (공지사항 경로) |
| UI | 중간 | 카페테리아 식별에 취약한 참조 동등성 사용 |
| UI | 낮음 | 카드 제목 구성이 도메인 계층이 아닌 레이아웃 위젯에 위치 |
| 스크롤 | 낮음 | `NestedPageScrollControllerGroup`이 알림 없이 `ChangeNotifier` 확장 |
| 스크롤 | 낮음 | `prevPage`가 드래그 세션 사이에 재설정되지 않음 |

**심각도 기준:**
`높음` — 현재 동작이 깨져 있거나 잘못 안내함
`중간` — 동작하지만 Flutter 관례에서 벗어나거나 향후 변경 시 문제 유발
`낮음` — 사소한 코드 품질, 발견 가능성, 또는 유지보수성 문제

---

## 11. 성능 최적화

이 섹션은 구조적 리팩토링 없이 적용 가능한 구체적이고 위험도가 낮은 성능 개선 사항을 식별합니다. 각 항목은 독립적으로 적용할 수 있습니다.

---

### 11-A. `AnimatedDateTitle` — 매 애니메이션 프레임마다 문자열 포맷 실행

**파일:** `lib/pages/home/home_app_bar.dart`

`AnimatedBuilder`는 탭 스와이프 중 초당 ~60회 빌더 콜백을 실행합니다. 빌더는 매 프레임마다 `string.getLocalizedDate(theDay.month, theDay.day, language)`를 호출하는데, 이는 switch문과 문자열 연결로 구성됩니다. 그러나 표시되는 텍스트는 스와이프 한 번당 단 한 번(`animation.value.round()`가 정수 경계를 넘을 때)만 바뀝니다.

주의 일곱 날짜 문자열은 `mondayOfWeek`와 `language`가 알려지는 시점(즉, 위젯 생성 시)에 이미 완전히 결정됩니다. 따라서 `List<String>`으로 미리 계산해 둘 수 있습니다:

```dart
// 한 번만 계산, AnimatedBuilder 바깥에서:
final dateLabels = List.generate(7, (i) {
  final day = mondayOfWeek.add(Duration(days: i));
  return string.getLocalizedDate(day.month, day.day, language);
});

// AnimatedBuilder 안에서 — 정수 인덱스 조회만:
return Text(dateLabels[displayIndex], ...);
```

이 패턴은 `AnimatedDateTitle`을 `StatefulWidget`으로 변환하거나(또는 부모에서 미리 계산하여 전달), `DateTime` 연산과 문자열 포맷을 60 fps 핫 패스에서 완전히 제거합니다.

---

### 11-B. 식사 버튼 애니메이션 후 불필요한 `setState`

**파일:** `lib/pages/home/home_page.dart`, `build` 내 버튼 핸들러

버튼 핸들러가 `setState`를 두 번 호출합니다: 한 번은 `_model.mealOfDay`를 업데이트하고 가드 플래그를 설정하며, 다른 한 번은 애니메이션 완료 후 플래그를 초기화합니다:

```dart
// 두 번째 setState — 가드 플래그만 초기화
setState(() {
  _isMealOfDayButtonTransition = false;
});
```

`_isMealOfDayButtonTransition`은 **`build` 메서드에서 읽히지 않습니다** — `this`(상태 객체)를 캡처하고 호출 시점에 필드 값을 읽는 `onPageChanged` 클로저 안에서만 읽힙니다. 따라서 두 번째 `setState`는 렌더링 변경 없이 `_HomePageState.build` 전체 리빌드를 트리거합니다(`Consumer`, AppBar, `dayOfMealLabel` switch 등 포함). 플래그는 `setState` 없이 초기화할 수 있습니다:

```dart
// 애니메이션 완료 후, 리빌드 불필요:
_isMealOfDayButtonTransition = false;
```

`mounted` 가드는 유지되어야 합니다. 첫 번째 `setState`(버튼 레이블을 위한 `_model.mealOfDay` 업데이트)는 여전히 필요합니다.

---

### 11-C. 끼니 전환 애니메이션 중 페이지 콘텐츠에 `RepaintBoundary`

**파일:** `lib/pages/home/nested_page_scroll.dart`

`animateToPageFromScroll` 또는 `animateToPage` 중 `PageView`가 세 페이지(아침/점심/저녁) 사이를 애니메이션합니다. 각 페이지의 콘텐츠—`MealCard` 위젯의 그리드—는 정적이며 애니메이션 중에 변하지 않습니다. `RepaintBoundary` 없이는 Flutter가 매 애니메이션 프레임마다 식사 카드 콘텐츠를 다시 래스터화할 수 있습니다.

`SingleChildScrollView` 콘텐츠(또는 전달된 `ConstrainedBox` 자식)를 `RepaintBoundary`로 감싸면 래스터라이저가 렌더링된 레이어를 캐시하여 페이지 슬라이드 중 다시 그리지 않고 컴포지팅합니다:

```dart
// NestedPageScrollView의 PageView.builder → itemBuilder:
child: RepaintBoundary(
  child: widget.builder(context, pageIndex),
)
```

이는 터치 드래그 페이지 전환과 포인터 스크롤 `animateToPageFromScroll` 경로 모두에 적용되며, 페이지당 단 하나의 추가 컴포지팅 레이어(총 3개)만 사용합니다.

---

### 11-D. `Consumer<BapUModel>`이 관련 없는 필드 변경에도 리빌드

**파일:** `lib/pages/home/home_page.dart`, `lib/main.dart`

`BapUModel`은 `language`와 `themeBrightness` 두 개의 관련 없는 필드를 보유합니다. `notifyListeners()`가 세분화되지 않아 모든 `Consumer<BapUModel>`이 **둘 중 어느** 필드가 변경되어도 리빌드됩니다.

구체적으로:
- `MyApp.build`의 `Consumer<BapUModel>`은 언어가 변경될 때 `MaterialApp`을 리빌드하는데, 언어가 `ThemeData`에 영향을 주지 않음에도 그렇게 합니다.
- `home_page.dart`에서 `WeekMealTabBarView`를 감싸는 `Consumer<BapUModel>`은 밝기 변경 시 전체 카드 그리드를 리빌드합니다. `WeekMealTabBarView`는 모델에서 `language`만 사용하며 테마는 `Theme.of(context)`를 통해 자동으로 전파됩니다.

Provider의 `Selector` 위젯은 파생 값을 구독하여 관련 없는 필드가 변경될 때 리빌드를 건너뛸 수 있게 합니다:

```dart
// language가 변경될 때만 리빌드, brightness 변경 시는 건너뜀:
Selector<BapUModel, Language>(
  selector: (_, model) => model.language,
  builder: (context, language, child) => WeekMealTabBarView(
    language: language, ...
  ),
)
```

가장 효과적인 위치는 `MyApp.build`이며, 언어 변경 시 `MaterialApp` 재생성을 모델 분리(§2c, §4c 참조)로 방지할 수 있습니다. 모델을 분리하지 않는다면 각 Consumer 위치에 `Selector`를 사용하는 것이 최소 변경입니다.

---

### 11-E. `MealCard`와 `DayOfWeekTabBar` — 빌드마다 HSL 변환 실행

**파일:** `lib/pages/home/meal_card.dart`, `lib/pages/home/home_app_bar.dart`

두 위젯 모두 `build`에서 `HSLColor.fromColor(...)`를 호출합니다:

```dart
// MealCard.build — 빌드마다 카드 하나당 한 번 실행
final primaryHsl = HSLColor.fromColor(theme.colorScheme.primaryContainer);

// DayOfWeekTabBar.build
final unselectedLabelColor = HSLColor.fromColor(colorScheme.onSurface)
    .withSaturation(0).withLightness(...).toColor();
```

이 값들은 테마가 변경될 때만 바뀝니다(드물게 발생하는 사용자 주도 이벤트). 이 파생 색상을 미리 계산하여 캐시하는 `ThemeExtension`이 빌드 경로에서 변환을 완전히 제거합니다. 위험이 낮고 추가적인 변경입니다:

```dart
// 한 번 정의, ThemeData에 첨부:
class BapUColors extends ThemeExtension<BapUColors> {
  final Color cardHeaderBackground;
  final Color cardHeaderText;
  final Color tabUnselectedLabel;
  ...
}
```

영향은 작지만(빌드당 몇 번의 HSL 연산), 재계산 비용이 있는 테마 파생 색상을 위한 Flutter 관용적 접근법입니다.

---

### 성능 최적화 요약

| # | 위치 | 효과 | 위험도 | 상태 |
|---|------|------|--------|------|
| 11-A | `AnimatedDateTitle` — 60fps 문자열 포맷 | **높음** (핫 패스) | 낮음 | ✅ 적용됨 |
| 11-B | 버튼 애니메이션 후 `setState` | 중간 | **매우 낮음** | ✅ 적용됨 |
| 11-C | 페이지 콘텐츠에 `RepaintBoundary` | 중간 (애니메이션 부드러움) | 낮음 | ⚠️ 롤백 — 페이지 전환 최초 렌더 시 화면 순간 암전 발생 |
| 11-D | `Consumer<BapUModel>` 대신 `Selector` | 중간 | 낮음~중간 | 미적용 |
| 11-E | `ThemeExtension`을 통한 HSL 캐시 | 낮음 | 낮음 | 미적용 |
