# 밥먹어U

UNIST 구내식당 메뉴를 확인할 수 있는 Flutter 애플리케이션입니다.

- 백엔드 API: `https://meal.hexa.pro/`
- 지원 플랫폼: Android, iOS, Web
- 라이선스: GPL-2.0

## 주요 기능

- 기숙사식당 / 학생식당 / 교직원식당 주간 식단 조회
- 캐시 우선 로딩 후 백그라운드 갱신
- 식단 카드 길게 눌러 메뉴 공유 (모바일)
- 다크 모드 / 라이트 모드 / 시스템 따라가기 선택
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

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 아키텍처와 파일별 역할
- [AGENTS.md](AGENTS.md) — AI 코딩 에이전트용 규약
- [docs/features/nested_page_scroll.md](docs/features/nested_page_scroll.md) — 커스텀 스크롤 시스템 분석

## 향후 작업

- 설정 화면 (테마 / 알레르기 / 알림 / 위젯 — 현재 알레르기·알림·위젯은 저장만 되는 플레이스홀더)
- 알레르기 경고 표시 (백엔드 API에 알레르겐 데이터 추가 필요)
- 키워드 푸시 알림 (`NotificationService` 및 구독 관리 필요)
- 홈 화면 위젯 (캐시가 `getApplicationSupportDirectory()`에 저장되어 위젯에서 접근 불가 — 별도 저장 경로 필요)
- 웹에서 메뉴 카드 호버 시 클립보드 복사 버튼
