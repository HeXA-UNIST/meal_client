# 밥먹어U

UNIST 구내식당 메뉴 뷰어 애플리케이션

[![App Store](https://img.shields.io/badge/App_Store-0D96F6?style=flat&logo=app-store&logoColor=white)](https://apps.apple.com/kr/app/%EB%B0%A5%EB%A8%B9%EC%96%B4u/id1628256171)
[![Google Play Store](https://img.shields.io/badge/Google_Play-414141?logo=google-play&logoColor=white)](https://play.google.com/store/apps/details?id=com.wjddnwls7879.unistbab)
[![Web](https://img.shields.io/badge/Web-brightgreen?style=flat&logo=googlechrome&logoColor=white&color=4285f4)](https://bapu.hexa.pro)

[![License: GPL 2.0](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=fff)](https://flutter.dev)

## 주요 기능

- 기숙사식당 / 학생식당 / 교직원식당 주간 식단 조회
- 한국어 / 영어 지원
- 식단 카드 길게 눌러 메뉴 공유 (모바일)
- Android/iOS 홈 화면 위젯
- 메뉴 키워드 알림
- 반응형 디자인
- 다크 모드 지원

## 개발

```bash
flutter pub get
flutter run                  # 디버그 실행
flutter analyze              # 정적 분석
flutter test                 # 전체 테스트
flutter build apk            # Android
flutter build ios            # iOS
flutter build web            # Web
```

ARB 변경 후에는 `flutter gen-l10n`으로 `lib/l10n/app_localizations*.dart`를 재생성해야 합니다.

## 문서

- [AGENTS.md](AGENTS.md) - AI 코딩 에이전트 규약
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - 아키텍처와 파일별 역할
- [docs/features/nested_page_scroll.md](docs/features/nested_page_scroll.md) - 커스텀 스크롤 시스템 분석
