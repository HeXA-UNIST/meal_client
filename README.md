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

- Android와 iOS에서는 화면에서 데이터를 갱신할 때와 백그라운드 작업에서 데이터를 갱신할 때 같은 로직을 사용합니다. 백그라운드 작업은 화면이 메모리에 보관하는 상태 대신 저장된 설정과 캐시를 읽어 로컬 알림을 예약합니다.
- 홈 화면 위젯은 네이티브 코드로 구현되어 있으며, Flutter가 저장한 식단과 운영 정보의 JSON 파일을 직접 읽습니다. 공유 캐시의 형식과 저장 방식은 앱과 위젯 모두에 영향을 줍니다.
- 화면에는 유효한 캐시의 데이터를 먼저 표시하고, 서버 응답을 받으면 내용을 갱신합니다.
- 식단의 날짜와 주차, 운영시간은 한국 시간(KST)을 기준으로 해석합니다. 사용자가 지정한 알림 시각은 기기의 현지 시간을 기준으로 하므로, 알림을 보낼 시각과 알림 대상 식단의 날짜를 구분합니다.
- `BapuSettings`는 앱 전역에서 사용하는 테마·언어·알림 설정을 관리합니다. 조회한 식단과 선택한 날짜·끼니 등 홈 화면에 필요한 상태는 해당 화면에서 관리합니다.
- 앱 화면과 네이티브 위젯은 같은 JSON을 사용하지만, 각 플랫폼의 코드가 데이터를 별도로 해석합니다.
- 데이터 조회와 로컬 저장의 성공 여부는 각각 판단합니다. 화면에서는 캐시 저장에 실패해도 서버 응답을 표시할 수 있지만, 백그라운드 작업에서는 현재 주 식단이나 안내 정보를 캐시에 저장하지 못하면 작업이 실패한 것으로 처리합니다.

### Directory Structure

```text
meal_client/
├── lib/
│   ├── main.dart                 # 앱 진입점, 테마
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
- **Home Widget:** `home_widget`, Android RemoteViews, iOS WidgetKit
- **Localization:** `flutter_localizations`, `intl`
- **Share API:** `share_plus`

## 오픈소스 라이선스

이 프로젝트는 [GNU General Public License v2.0](LICENSE)에 따라 배포됩니다.

Copyright © 2024-2026 HeXA.
