# develop-widget 통합 참고 노트

이 문서는 `develop-widget` 브랜치를 나중에 `develop`에 통합할 때 충돌과 서명 리스크를 줄이기 위한 참고 문서입니다. 현재 `develop-widget`의 목표는 Android 네이티브 위젯을 `/v2/menu`/`/v2/info` 기반 cache-only 구조로 전환하고, 이후 iOS WidgetKit 확장을 붙일 수 있는 공유 캐시 경계를 준비하는 것입니다.

## 통합 원칙

- 네이티브 위젯은 네트워크를 직접 호출하지 않습니다. 데이터 갱신의 단일 owner는 Flutter/Dart foreground 또는 Workmanager background refresh입니다.
- 공유 캐시는 raw API 파일인 `meal.json`과 `info.json`으로 제한합니다. 앱 전용 설정/기타 데이터를 App Group이나 위젯 공유 영역으로 옮기지 않습니다.
- Android 위젯은 `context.filesDir`의 `meal.json`/`info.json`만 읽고, iOS WidgetKit 위젯은 App Group container의 같은 파일만 읽어야 합니다.
- Dart는 iOS App Group ID를 하드코딩하지 않습니다. App Group container path는 native bridge가 반환합니다.
- `develop` 자체가 위젯 없이 온전하게 빌드/실행되어야 한다면 iOS App Group entitlement와 bridge는 미리 단독 반영하지 않습니다.

## 현재 develop-widget 변경 요약

### Dart shared cache

- `MealCache`는 `meal.json` raw `/v2/menu` 응답을 공유 캐시에 씁니다.
- `InfoRefreshService`와 `InfoCache`는 `/v2/info` 응답을 검증한 뒤 `info.json` raw cache로 씁니다.
- `core/widget_shared_storage.dart`는 위젯 공유 캐시 전용 conditional export입니다.
- Android에서는 기존 앱 파일 영역과 네이티브 `context.filesDir`가 같은 위치를 보도록 유지합니다.
- iOS에서는 `widget_shared_storage_io.dart`가 native bridge를 통해 App Group container path를 조회합니다.

### Android native widget

- `BapUWidgetMealRepository`는 fresh `meal.json`만 읽습니다. missing/stale/corrupt cache는 빈 메뉴 상태로 처리합니다.
- `BapUWidgetMealParser`는 `/v2/menu` v2 구조를 파싱합니다. `REGULAR` section만 표시하고, 영어 메뉴명이 없으면 한국어로 fallback합니다.
- `BapUWidgetOperatingHours`는 `info.json`을 필수 입력으로 읽어 운영 상태와 오늘의 끼니 전환 경계를 계산합니다. `info.json`이 없거나 깨졌거나 breakfast/lunch 전환 계산에 필요한 운영시간이 없으면 위젯 데이터 오류를 표시합니다.
- `BapUWidgetScheduleManager`는 AlarmManager로 자정, `info.json`에서 계산한 끼니 전환 경계, 운영 시작, 마감임박 시작, 운영 종료 경계를 예약합니다.
- provider XML의 `android:updatePeriodMillis`는 `0`입니다. 표시 전환은 AlarmManager와 Dart refresh 후 render trigger가 담당합니다.
- `BapUWidgetUpdateWorker`는 legacy WorkManager class 이름 보존용 shim입니다. active render path가 아닙니다.

### Widget render bridge

- Android는 로컬 Flutter plugin `plugins/bapu_widget_bridge`가 `pro.hexa.meal.meal_client/widget` MethodChannel을 등록합니다.
- plugin은 foreground Activity에 의존하지 않고 background/headless engine에서도 등록되어야 합니다.
- Dart background refresh는 `DartPluginRegistrant.ensureInitialized()` 이후 `refreshWidgets(throwOnFailure: true)`를 호출합니다.
- Android bridge는 `BapUWidgetUpdateDispatcher.renderAllWidgets(applicationContext)`를 호출합니다.
- iOS bridge는 같은 MethodChannel에서 `WidgetCenter.shared.reloadAllTimelines()`를 호출합니다.

### iOS 준비 상태

- `ios/Runner/AppDelegate.swift`에 App Group path 조회 channel과 WidgetKit reload channel이 있습니다.
- `ios/Runner/Info.plist`에는 `BAPU_APP_GROUP_IDENTIFIER = $(APP_GROUP_IDENTIFIER)`가 있습니다.
- `ios/Runner/Runner.entitlements`에는 App Group entitlement가 있습니다.
- `ios/Runner.xcodeproj/project.pbxproj`에는 Runner target build setting의 `APP_GROUP_IDENTIFIER`와 `CODE_SIGN_ENTITLEMENTS`가 추가되어 있습니다.
- 실제 iOS WidgetKit extension target과 `TimelineProvider`는 아직 없습니다.

## develop에 선반영하지 말아야 할 범위

`develop`에 iOS 위젯 extension이나 Dart shared cache seam이 없는 상태에서 App Group bridge만 먼저 넣는 것은 권장하지 않습니다.

- App Group entitlement는 Apple Developer capability와 provisioning profile 상태에 영향을 받습니다.
- extension target이 없으면 App Group path bridge와 `WidgetCenter.reloadAllTimelines()`는 사용자 기능을 추가하지 않으면서 iOS 서명 실패 가능성만 늘립니다.
- `develop`을 위젯 없이 독립적으로 유지하려면 iOS bridge는 `develop-widget` 통합 시점 또는 iOS WidgetKit 작업 브랜치에서 함께 반영하는 편이 안전합니다.

## 병합 권장 순서

1. Dart shared cache 기반부터 병합합니다.
   `StorageKeys.infoCacheFile`, `core/widget_shared_storage*`, `MealCache`, `InfoCache`, `InfoRefreshService`, `info_data_source.dart` 변경을 먼저 맞춥니다.
2. Android 위젯 cache-only refactor를 병합합니다.
   Kotlin parser/repository/operating hours/time/dispatcher와 provider XML `updatePeriodMillis=0` 변경을 함께 가져옵니다.
3. Android background-safe render bridge를 병합합니다.
   `plugins/bapu_widget_bridge`, `pubspec.yaml`, `MainActivity.kt`, `widget_service*.dart`, background refresh의 widget refresh 호출을 한 묶음으로 봅니다.
4. iOS App Group bridge는 App Group provisioning과 iOS widget extension 계획이 확정된 뒤 병합합니다.
   `AppDelegate.swift`, `Info.plist`, `Runner.entitlements`, Xcode project setting이 한 세트입니다.
5. 마지막으로 iOS WidgetKit extension target과 timeline provider를 추가합니다.
   extension은 App Group의 `meal.json`/`info.json`만 읽고, Flutter 앱 저장소 내부를 직접 참조하지 않습니다.

## 충돌 예상 지점

- 문서: `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`
- Flutter dependencies: `pubspec.yaml`, `pubspec.lock`
- shared cache: `lib/core/constants.dart`, `lib/core/widget_shared_storage*.dart`
- meal refresh: `lib/features/meal/meal_cache.dart`, `meal_refresh_service.dart`, `meal_background_refresh_io.dart`
- info refresh: `lib/features/info/info_cache.dart`, `info_refresh_service.dart`, `info_data_source.dart`
- widget service: `lib/features/widget/widget_service*.dart`
- Android native widget: `android/app/src/main/kotlin/pro/hexa/meal/meal_client/BapUWidget*.kt`
- Android provider XML: `android/app/src/main/res/xml/widget_info_*.xml`
- Android bridge plugin: `plugins/bapu_widget_bridge/`
- iOS bridge/signing: `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj`

## 검증 체크리스트

Windows/Android/Web에서 확인할 항목:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `.\gradlew.bat :app:testDebugUnitTest`
- `flutter build web --debug`
- `flutter build apk`
- Android 실기기 또는 에뮬레이터에서 위젯 추가, 위젯 설정, cache miss/stale 상태, background refresh 후 갱신 확인

macOS/Xcode에서 추가로 확인할 항목:

- `flutter build ios --no-codesign`
- Xcode Runner target signing/capability 확인
- Apple Developer에서 `group.com.wjddnwls7879.unistbab` App Group이 앱 target과 향후 widget extension target 모두에 연결되어 있는지 확인
- iOS BGTask/headless 경로에서 App Group path 조회와 `WidgetCenter.reloadAllTimelines()`가 foreground `UIViewController` 없이 도달하는지 확인
- WidgetKit extension 추가 후 실제 기기에서 timeline entry 전환 확인

## iOS WidgetKit 설계 메모

iOS는 Android AlarmManager처럼 원하는 시각에 프로세스를 깨우는 모델이 아닙니다. `TimelineProvider`가 미리 제공한 timeline entry를 시스템이 적절한 시각에 표시합니다.

cache-only iOS 위젯의 timeline에는 최소한 다음 경계를 entry로 넣습니다.

- 자정
- `info.json`에서 계산한 breakfast/lunch 전환 시각
- 운영 시작
- 마감임박 시작
- 운영 종료

“N분 남음” 같은 분 단위 countdown은 WidgetKit에서 안정적으로 보장되지 않습니다. iOS 위젯은 `open`/`closing soon`/`closed` 같은 coarse 상태를 우선 표현하고, 정확한 분 단위 표시는 Android에만 유지하거나 iOS에서 staleness를 감수해야 합니다.

## 잔여 리스크

- iOS BGAppRefresh 실행 시각은 시스템 제어입니다. Android Workmanager와 같은 주기성을 기대하면 안 됩니다.
- iOS App Group signing/provisioning은 Windows에서 검증할 수 없습니다.
- Android RemoteViews는 단위 테스트로 시각 회귀를 충분히 잡기 어렵습니다. 최종 병합 전 실기기 위젯 렌더링 검증이 필요합니다.
- `/v2/info` 운영시간 schema가 바뀌면 Android/iOS 위젯 운영 상태가 함께 깨질 수 있습니다. parser 테스트와 실데이터 smoke test를 유지해야 합니다.
