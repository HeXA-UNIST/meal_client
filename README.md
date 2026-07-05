# 밥먹어U

UNIST 구내식당 메뉴를 확인할 수 있는 애플리케이션입니다.

[![App Store](https://img.shields.io/badge/App_Store-0D96F6?style=flat&logo=app-store&logoColor=white)](https://apps.apple.com/kr/app/%EB%B0%A5%EB%A8%B9%EC%96%B4u/id1628256171)
[![Google Play Store](https://img.shields.io/badge/Google_Play-414141?logo=google-play&logoColor=white)](https://play.google.com/store/apps/details?id=com.wjddnwls7879.unistbab)
[![Web](https://img.shields.io/badge/Web-brightgreen?style=flat&logo=googlechrome&logoColor=white&color=4285f4)](https://bapu.hexa.pro)

[![License: GPL 2.0](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=fff)](https://flutter.dev)

## 주요 기능

- 기숙사식당 / 학생식당 / 교직원식당 주간 식단 조회
- 한국어 / 영어 메뉴명 표시 (영어 미제공 메뉴는 한국어로 표시)
- 식단 카드 길게 눌러 메뉴 공유 (모바일)
- 메뉴 키워드 알림 (시간대별 백그라운드 검사, 매칭되면 로컬 알림)
- 반응형 디자인
- 다크 모드 지원
- 한국어 / 영어 지원

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

ARB 변경 후에는 `flutter gen-l10n`으로 `lib/l10n/app_localizations*.dart`를 재생성합니다.

## 문서

- [AGENTS.md](AGENTS.md) — AI 코딩 에이전트용 규약
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 아키텍처와 파일별 역할
- [docs/features/nested_page_scroll.md](docs/features/nested_page_scroll.md) — 커스텀 스크롤 시스템 분석

## 향후 작업

- 설정 화면 (테마 / 알레르기 / 알림 / 위젯 — 현재 알레르기·위젯은 저장만 되는 플레이스홀더, 알림은 실제로 동작)
- 알레르기 경고 표시 (`/v2/menu`의 메뉴별/섹션별 알레르겐 데이터 사용)
- 특별식 / 간편식 / 샐러드바 등 비정규 섹션 표시 및 섹션 제목 표시
- 키워드 알림 실기기 스케줄링 QA (Android/iOS 정확한 시각 동작 검증)
- 홈 화면 위젯 (공유 캐시 경계(`core/widget_shared_storage.dart`)는 준비됨 — `develop-widget` 브랜치의 네이티브 구현 병합 필요)
- 웹에서 메뉴 카드 호버 시 클립보드 복사 버튼
