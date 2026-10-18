# 밥먹어U
![밥먹어U 로고](./assets/imgs/preview.png)

UNIST 구내식당 식단표 뷰어

[![App Store](https://img.shields.io/badge/App_Store-0D96F6?style=flat&logo=app-store&logoColor=white)](https://apps.apple.com/kr/app/%EB%B0%A5%EB%A8%B9%EC%96%B4u/id1628256171)
[![Google Play Store](https://img.shields.io/badge/Google_Play-414141?logo=google-play&logoColor=white)](https://play.google.com/store/apps/details?id=com.wjddnwls7879.unistbab)
[![Web](https://img.shields.io/badge/Web-brightgreen?style=flat&logo=googlechrome&logoColor=white&color=4285f4)](https://bapu.hexa.pro)

[![License: GPL 2.0](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-0553B1?logo=flutter&logoColor=fff)](https://flutter.dev)

## Requirements

- Android 앱: Android 9(SDK 28) 이상
- iOS 홈 화면 위젯: iOS 17 이상

## 주요 기능

| 기능 | Android | iOS | Web |
| --- | :---: | :---: | :---: |
| 주간 식단 조회 | ✅ | ✅ | ✅ |
| 다음 주 식단 미리보기 | ✅ | ✅ | ✅ |
| 식당 운영시간 확인 | ✅ | ✅ | ✅ |
| 영어 지원 | ✅ | ✅ | ✅ |
| 다크모드 지원 | ✅ | ✅ | ✅ |
| 식단 카드 길게 눌러 메뉴 공유 | ✅ | ✅ | ⛔ |
| 식단 알림 | ✅ | ✅ | ⛔ |
| 홈 화면 식단 위젯 | ✅ | ✅ | ⛔ |
| 알레르기 유발식품 경고 | 🟡 | 🟡 | ⛔ |

| 표시 | 의미 |
| --- | --- |
| ✅ | 현재 지원 (Supported) |
| 🟡 | 구현 예정 (Not implemented yet; planned) |
| ⛔ | 구현 계획 없음 (Will not be implemented) |

## Getting Started

1. [Flutter 설치 안내](https://docs.flutter.dev/install/quick)에 따라 SDK를 설치하세요. [pubspec.yaml](pubspec.yaml)이 요구하는 Flutter 버전을 사용해야 합니다.

2. 저장소를 복제한 뒤, 원하는 플랫폼에서 앱을 실행하거나 빌드하세요. iOS 앱을 실행하거나 빌드하려면 macOS와 Xcode가 필요합니다.

```bash
git clone https://github.com/HeXA-UNIST/meal_client.git
cd meal_client
flutter pub get
flutter run
```

### Test

Flutter 코드를 분석하고 테스트하려면 다음 명령을 실행하세요.

```bash
flutter analyze
flutter test
```

Android 앱을 한 번 실행하거나 빌드하여 Gradle Wrapper를 준비한 뒤, 다음 명령으로 네이티브 단위 테스트를 실행하세요.

```bash
./android/gradlew -p android :app:testDebugUnitTest
```

실제 TextView의 본문 크기 선택·2열 공통 크기·말줄임을 검사하려면 Android 실기기를 연결하거나 에뮬레이터를 실행한 뒤 아래 명령을 사용하세요. 이 검증은 위 JVM 테스트와 별도로 실행합니다.

```bash
./android/gradlew -p android :app:connectedDebugAndroidTest
```

Windows에서는 `./android/gradlew` 대신 `.\android\gradlew.bat`을 사용하세요.

iOS 네이티브 테스트는 macOS에서 사용 가능한 시뮬레이터를 확인하고, `SIMULATOR_UDID`를 사용할 시뮬레이터의 UDID로 바꿔서 실행하세요.

```bash
xcrun simctl list devices available
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=SIMULATOR_UDID'
```

## Architecture

- `AppSettings`는 앱 설정을 관리하고 설정값을 `shared_preferences`에 저장합니다.
- `/v2/menu`에서 식단을, `/v2/info`에서 최신 식당 운영 시간과 공지를 가져옵니다.
  - Android와 iOS 앱은 받은 JSON을 캐시에 저장해 홈 화면 위젯과 공유합니다.
  - 요청을 보내기 전 유효한 캐시가 있으면 해당 데이터를 먼저 표시하고, 최신 응답을 받으면 화면을 갱신합니다.
  - Android와 iOS의 식단·안내 정보 요청은 저장된 JSON의 `etag`로 재검증하고, 304이면 기존 본문을 재사용합니다.
  - 웹에서는 별도의 파일 캐시를 사용하지 않습니다.
  - `/v2/menu`에서 다음 주 시작일을 제공할 경우(=다음 주 식단이 업로드되었다는 의미) 앱은 다음 주 식단을 가져와 표시합니다.
- Android와 iOS 앱은 `workmanager`를 통해 백그라운드 데이터 갱신 작업을 등록하고, 사용자 설정과 식단 캐시를 바탕으로 로컬에서 식단 알림을 예약합니다.

Android 식단 알림은 알림 표시 권한과 정확한 알람 특별 접근이 모두 필요합니다.
알림을 켜면 필요한 권한을 요청하며, Android 12 이상에서는 시스템의
‘알람 및 리마인더’ 설정 화면에서 정확한 알람을 허용합니다. 권한이 철회되면
앱의 알림 설정은 유지하고 예약을 중단합니다. 알림에 필요한 권한이 없는 동안 Android와 iOS 모두 앱 실행 시 안내 팝업을 표시하며,
알림 설정 화면에서도 권한을 복구할 수 있습니다.
권한을 다시 허용하면 네트워크 없이 저장된 식단과 설정으로 알림 예약을 복구합니다.
위젯은 정확한 알람 권한이 없을 때 식단 대신 권한 안내를 표시합니다.
식단 알림과 위젯 운영 상태 전환은 `setExact()`로 예약합니다.
서버 데이터 갱신은 기존 WorkManager 작업이 맡습니다.

### Directory Structure

```text
meal_client/
├── lib/
│   ├── main.dart                 # 앱 시작점과 테마
│   ├── core/                     # API, 네트워크, 공유 저장소
│   ├── domain/                   # 식단 데이터 모델
│   ├── features/
│   │   ├── home/                 # 주간 식단 메인 화면
│   │   ├── meal/                 # 식단 요청과 캐시
│   │   ├── info/                 # 공지/운영시간 요청과 캐시
│   │   ├── settings/             # 앱 설정 화면
│   │   ├── notification/         # 식단 알림 예약
│   │   └── widget/               # 홈 화면 위젯
│   └── l10n/                     # 한국어/영어 번역
├── android/                      # Android 앱, 홈 화면 위젯
├── ios/                          # iOS 앱, WidgetKit 위젯
└── web/                          # 웹 앱 리소스
```

### Tech Stack

- **State Management:** `provider`
- **Network:** `http`, Android `cronet_http`, iOS `cupertino_http`
- **Local Storage:** `shared_preferences`, `path_provider`
- **Notification & Background task:** `flutter_local_notifications`, `timezone`, `workmanager`
- **Home Widget:** `home_widget` 갱신 요청, Android RemoteViews, iOS WidgetKit
- **Localization:** `flutter_localizations`, `intl`
- **Share API:** `share_plus`

### 위젯 갱신 경로

Flutter의 foreground/Workmanager는 공유 JSON 캐시를 저장한 뒤
`HomeWidget.updateWidget()`으로 갱신을 요청합니다.

- Android: `APPWIDGET_UPDATE` → 기존 provider → 단일 렌더 큐 → RemoteViews.
  다음 운영 상태 전환은 기존 AlarmManager가 예약합니다.
- iOS: `BapUWidget` timeline 갱신 요청 → 기존 AppIntentTimelineProvider → SwiftUI.
- 공유 캐시와 iOS App Group 경로·백업 제외 채널은 기존 구현을 사용합니다.
  `home_widget`의 별도 데이터 저장소와 generator는 사용하지 않습니다.

자체 Android 플러그인과 iOS 갱신 채널은 제거했지만, 식단 해석·위젯별 식당 설정·
시간 경계 계산·UI는 네이티브 구현으로 남습니다. `home_widget 0.10.0`은
Android Glance 의존성을 포함하므로, 자체 코드 감소가 의존성 감소를 뜻하지는 않습니다.

Android에서 갱신 요청의 완료는 broadcast 전송 완료를 뜻합니다. 실제 렌더·예약 실패는
네이티브 로그에 남으며 Flutter의 `throwOnFailure`로 전달되지 않습니다.
따라서 Workmanager는 요청 실패는 재시도할 수 있지만, 이후의 렌더 실패는 감지하지 못합니다.

Android 렌더·예약 오류는 처리한 경계에서 `logWidgetFailure(stage, error)`로 한 번 기록합니다.
dispatcher가 기록한 오류를 설정 화면·권한 복구 완료 콜백에서 다시 기록하지 않습니다.
여러 위젯의 실패와 렌더·예약 동시 실패는 원인 예외와 `suppressed`로 보존하며,
오류가 나도 다음 예약과 완료 처리는 계속 시도합니다.
Firebase 통합 시 이 함수에 non-fatal 보고를 연결하고, 기존 브랜치의 보고 호출과 중복되지 않게 정리합니다.
정상적인 메뉴 생략이나 최초 실행 전 캐시 부재는 표시·복구 정책에 따라 처리할 상태입니다.

## 오픈소스 라이선스

이 프로젝트는 [GNU General Public License v2.0](LICENSE)에 따라 배포됩니다.

Copyright © 2024-2026 HeXA.
