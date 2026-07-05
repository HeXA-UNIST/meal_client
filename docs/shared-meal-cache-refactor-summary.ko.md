# 공유 식단 캐시 리팩터링 요약

> **문서 상태**: 이 문서는 최초 공유 캐시 리팩터링(`79f8ca8`, 2026-05-24) 시점의 기록이다. 이후 진행된 Android cache-only 위젯 전환(`eb5169a`, `c961da1`)과 `bapu_widget_bridge` 렌더 브리지 도입으로, 아래 "네이티브 Android 위젯 통합"의 native fallback 서술과 "현재 백그라운드 작업의 책임"의 위젯 MethodChannel 미호출 서술은 더 이상 유효하지 않다(네이티브 위젯은 현재 network fallback 없이 cache-only로 렌더링하며, 백그라운드 새로고침은 `refreshWidgets()`를 호출한다). 현재 아키텍처는 [`ARCHITECTURE.md`](ARCHITECTURE.md)와 [`develop-widget-integration-notes.ko.md`](develop-widget-integration-notes.ko.md)를 참고한다.

## 목적

이번 리팩터링은 식단 API의 원본 JSON을 앱, Workmanager 백그라운드 새로고침, 향후 추가될 로컬 알림, 향후 추가될 홈 화면 위젯이 공통으로 사용하는 단일 캐시 소스로 만든다.

이전에는 포그라운드 식단 로딩이 `meal_data_source.dart` 안에서 직접 데이터를 fetch·캐시했고, 알림/위젯 구현 브랜치들이 각자 별도의 백엔드 fetch 경로를 추가할 가능성이 높았다. 그 결과 캐시/freshness 동작이 중복되고 브랜치 간 충돌이 발생할 수 있었다.

이번 변경 이후, 피처 코드는 `ApiConstants.mealEndpoint`를 직접 fetch하지 말고 `MealCache`와 `MealRefreshService`를 사용해야 한다.

## 주요 변경 사항

### KST 주 단위 Freshness

- `lib/core/constants.dart`에 `MealTimeConfig.kstWeekId(DateTime time)`를 추가했다.
- 기존의 연도 기반 주차 계산 로직을 1970-01-05(월요일) 기준의 단조 증가형 KST 주 ID로 교체했다.
- 캐시 freshness 규칙은 기존 제품 규칙을 유지한다: 캐시 파일의 `lastModified`가 현재 KST 메뉴 주(週)에 속할 때 fresh로 판정한다.

### 표준 식단 캐시

- `lib/features/meal/meal_cache.dart`를 추가했다.
- `MealCache`는 기존 플랫폼 저장소 레이어를 감싼다:
  - 네이티브: `getApplicationSupportDirectory()/meal.json`
  - 웹: 영구 캐시 없음. 저장소 메타데이터를 사용할 수 없을 때 freshness는 `false`를 반환한다.
- 캐시는 원본 API JSON만 저장한다. 별도의 래퍼 JSON이나 `updatedAt` 메타데이터는 없다.

공개 계약:

```dart
Future<void> writeRawMealJson(String rawJson);
Future<String> readRawMealJson();
Future<DateTime> getRawMealUpdatedAt();
Future<bool> hasFreshMealCache(DateTime now);
```

### 공유 새로고침 서비스

- `lib/features/meal/meal_refresh_service.dart`를 추가했다.
- `MealRefreshService.refreshMealData()`는 항상 백엔드를 fetch하고, 원본 JSON을 검증·파싱한 뒤, 유효하고 비어 있지 않은 배열 응답일 때만 `MealCache`에 기록하고, 파싱된 `WeekMeal`을 반환한다.
- `MealRefreshService.getFreshOrRefreshMealData()`는 먼저 fresh 캐시를 읽고, 캐시가 stale·없음·손상 상태인 경우 백엔드 fetch로 폴백한다.

### Meal Data Source 재작성

- `lib/features/meal/meal_data_source.dart`를 fetch/캐시/freshness 로직의 소유자에서, 기존 UI 호출자를 위한 얇은 호환 진입점으로 재작성했다.
- `fetchAndCacheMealData()`는 이제 `MealRefreshService.refreshMealData()`로 위임한다.
- `getCachedMealData()`는 freshness 판정과 raw 읽기를 `MealCache`에 위임한 뒤, raw JSON을 `WeekMeal`로 파싱한다.
- 이렇게 함으로써 `HomePage`의 import는 유지하면서 공유 캐시 동작을 알림/위젯에서 재사용 가능한 서비스로 옮겼다.

### 기존 HomePage 동작 유지

`HomePage`는 현재 UX를 그대로 유지한다:

- 캐시가 있으면 먼저 캐시된 식단 데이터를 표시한다.
- 그 후 항상 포그라운드에서 fresh fetch를 수행한다.

내부 구현은 공유 캐시/새로고침 배관을 거치게 바뀌었지만, 포그라운드 앱 진입 시 동작을 "캐시 전용"으로 변경하지는 않았다.

### Workmanager 백그라운드 새로고침

- 조건부 백그라운드 새로고침 파일을 추가했다:
  - `meal_background_refresh.dart`
  - `meal_background_refresh_io.dart`
  - `meal_background_refresh_stub.dart`
- `main()`은 `WidgetsFlutterBinding.ensureInitialized()` 이후 백그라운드 새로고침을 초기화한다.
- 네이티브 플랫폼은 1시간 주기의 `bapu_meal_refresh` 주기 작업을 등록한다.
- 웹은 no-op 구현을 사용한다.
- Workmanager 콜백에는 `@pragma('vm:entry-point')`를 붙였다.
- 백그라운드 isolate는 식단 새로고침 전에 자체적으로 Flutter binding을 초기화한다.
- 향후 알림 평가가 추가되면, 해당 dispatcher도 알림 설정을 읽기 전에 백그라운드 isolate 안에서 `SharedPreferences`를 초기화하고 `AppSettings`를 생성해야 한다.
- Android 등록은 `NetworkType.connected` 제약을 사용한다. iOS는 `BGAppRefreshTaskRequest`가 이 제약을 강제하지 않기 때문에 동일한 Workmanager 네트워크 제약이 적용되지 않는다.

현재 백그라운드 작업의 책임:

- 식단 데이터를 `MealCache`로 새로고침한다.
- 위젯 MethodChannel 호출은 하지 않는다.
- 알림 매칭은 아직 하지 않는다.

### iOS 백그라운드 설정

- `ios/Runner/AppDelegate.swift`에서 백그라운드 isolate용 Workmanager 플러그인을 등록하고, 주기 새로고침 식별자를 등록하도록 수정했다.
- 프로젝트의 배포 타깃이 iOS 14.0이므로 iOS 13 availability 가드 없이 주기 작업을 곧바로 등록한다.
- `ios/Runner/Info.plist`를 다음 키로 업데이트했다:
  - `BGTaskSchedulerPermittedIdentifiers`
  - `UIBackgroundModes`의 `fetch`

iOS 백그라운드 실행은 best-effort이며, 정확한 시각이 보장되는 알림 인프라로 취급해서는 안 된다.
Workmanager 등록에 사용되는 `NetworkType.connected` 제약은 Android에서만 강제되며, iOS 백그라운드 새로고침은 동일한 네트워크 제약 의미 없이 시도될 수 있다.

### `home_widget` 제거

- 사용하지 않는 `home_widget` 의존성을 `pubspec.yaml`에서 제거했다.
- `pubspec.lock`을 갱신했다.
- `home_widget`이 compileSdk 37과 Android Gradle Plugin 9.1.0을 요구하는 AndroidX Glance 의존성을 끌고 와 발생하던 Android 빌드 실패가 이로써 해소되었다.

### 네이티브 Android 위젯 통합

- `develop-widget` 위로 리베이스하면서 네이티브 Android 위젯 프로바이더, 설정 액티비티, 레이아웃, 주기 위젯 워커를 모두 유지했다.
- `BapUWidgetFetcher.fetch(context)`는 이제 `context.filesDir/meal.json`을 먼저 읽는데, 이 파일은 Flutter가 Android에서 기록하는 raw 캐시 파일과 동일하다.
- 네이티브 위젯의 캐시 freshness는 Dart와 동일하게 파일 `lastModified`와 현재 시각을 단조 KST 주 ID 규칙으로 비교해 판정한다.
- 기존 네이티브 네트워크 fetch는 공유 캐시가 없거나, stale이거나, 유효하지 않을 때의 폴백으로만 남아 있다. 폴백 응답이 성공하면 파싱 후에 `meal.json`에 다시 기록한다.
- 위젯 업데이트 진입점들이 모두 `Context`를 `BapUWidgetFetcher`에 전달하도록 변경하여, 프로바이더·설정 화면·`BapUWidgetUpdateWorker`가 모두 캐시 우선 로딩을 사용한다.

### 캐시 견고성

- 네이티브 Dart 캐시 쓰기는 임시 파일에 기록한 뒤 원본 파일명으로 rename하는 방식을 사용하여, 읽는 쪽이 부분적으로 기록된 `meal.json`을 보지 않도록 한다.
- 캐시 freshness 확인이 실패하면 stale을 반환하기 전에 stack trace와 함께 로그를 남긴다. 저장소/플러그인 회귀가 단순한 캐시 미스로 묻히지 않도록 하기 위함이다.
- 포그라운드 위젯 새로고침 MethodChannel 실패는 debug assert 내부에서만이 아니라 release 빌드에서도 로그를 남긴다.

### Android Desugaring

- `android/app/build.gradle.kts`에서 core library desugaring을 활성화했다.
- `com.android.tools:desugar_jdk_libs:2.1.4`를 추가했다.
- `flutter_local_notifications` 21.0.0이 요구하는 사항이다.

## 추가된 테스트

- `test/domain_test.dart`의 KST 주 ID 경계값 테스트.
- `test/features/meal/meal_cache_test.dart`의 `MealCache` 테스트.
- `test/features/meal/meal_refresh_service_test.dart`의 `MealRefreshService` 테스트.

커버되는 동작:

- UTC/연도 경계를 넘는 같은 KST 주
- 같은 KST 주 안의 월요일과 일요일이 같은 ID를 가짐
- 월요일 00:00 KST 주 경계 전환
- 1월 1일이 일요일인 엣지 케이스
- raw JSON 쓰기/읽기 계약
- 파일 `lastModified` 기반 fresh/stale 캐시 감지
- 웹/no-cache 스타일의 메타데이터 실패 시 stale 반환
- fresh 캐시일 때 네트워크 fetch 회피
- stale 캐시일 때 백엔드 응답을 fetch 후 저장
- 손상된 fresh 캐시일 때 백엔드 fetch로 복구

## 검증

통과한 항목:

```bash
flutter analyze                  # 이슈 없음
flutter test                     # 56개 테스트 통과
flutter build apk --debug         # app-debug.apk 빌드 완료
```

APK 산출물:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

Android 빌드에서 Gradle 8.13.0과 Kotlin 2.1.0에 대한 향후 deprecation 경고가 여전히 출력되지만, 현재 빌드를 막는 요인은 아니다.

## 통합 가이드

### 로컬 알림 브랜치

알림 코드는 `fetchRawString(ApiConstants.mealEndpoint)`를 직접 호출하지 말아야 한다.

다음과 같이 사용한다:

```dart
final meal = await MealRefreshService().getFreshOrRefreshMealData();
```

그런 다음 `AppSettings.notification`을 해당 `WeekMeal`에 대해 평가한다.

이미 알림 브랜치가 직접 백엔드 fetch를 추가한 상태라면, 그 fetch 경로를 `MealRefreshService`로 교체한다.

### 위젯 브랜치

위젯은 공유된 raw `meal.json` 캐시를 데이터 소스로 사용해야 한다.

Android 네이티브 위젯의 경우, 동일한 앱 내부 raw JSON 파일을 읽고, 파일 `lastModified`에 동일한 KST freshness 규칙을 적용한다. 네이티브 Kotlin은 단조 KST 주 ID 로직을 동일하게 미러링해야 한다.

향후 iOS WidgetKit을 도입할 경우, App Group 컨테이너가 필요하면 물리적 저장 위치를 `MealCache` 뒤로 옮기되, 위젯 전용 캐시 포맷을 따로 도입하지 말고 페이로드는 동일한 raw 식단 API JSON을 그대로 유지한다.

## 남은 후속 작업

- `MealRefreshService` 위에 알림 매칭/표시 로직을 구현한다.
- 알림 타이밍 요구사항이 확정되면 iOS 백그라운드 동작을 재검토한다.
- 프로젝트 Android Gradle 설정과 호환되는 의존성/툴체인 경로를 결정한 뒤에만 위젯 패키지나 네이티브 위젯 구현을 다시 도입한다.
- Gradle·Kotlin 버전에 대한 Flutter 경고는 추후 해결한다.