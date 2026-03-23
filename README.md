# 밥먹어U

UNIST의 구내식당 메뉴를 확인할 수 있는 애플리케이션입니다.

## 주요 기능

- 기숙사식당, 학생식당, 교직원식당 주간 식단 조회
- 식단표 캐시 우선 로딩
- 식단 카드 길게 눌러서 메뉴 공유
- 다크 모드 자동 적용
- 영어 지원 (WIP)
- 웹 버전 (WIP)

## TODO (우선순위순)
- 문서화
- 영어 지원 개선 (i18n / l10n)
  - Flutter에서 공식적으로 지원하는 국제화 패키지 및 프레임워크로 전환
  - 모든 기능에 영향을 주기 때문에, 최우선적으로 수정해야 함
- 설정 화면 및 설정 모델 구현
- 위젯 구현
  - 주의: 식단표를 `getApplicationSupportDirectory()`에 저장하지만, 위젯에서는 이 데이터에 접근할 수 없음.
- 테마 구현 개선
  - Flutter의 공식 테마 시스템으로 전환하여 관리. 일단 잘 작동하니 우선순위는 낮음.
- 꾹 눌러서 공유 시 햅틱 피드백 추가

## 프로젝트 구조

```text
meal_client/
├── lib/
│   ├── pages/
│   │   ├── home/
│   │   │   ├── home_page.dart
│   │   │   ├── home_app_bar.dart
│   │   │   ├── meal_card.dart
│   │   │   ├── nested_page_scroll.dart
│   │   │   └── week_meal_view.dart
│   │   ├── home.dart
│   │   └── home_drawer.dart
│   ├── api_v2.dart
│   ├── data.dart
│   ├── i18n.dart
│   ├── main.dart
│   ├── meal.dart
│   ├── model.dart
│   ├── platform_http_client*.dart
│   └── storage*.dart
├── assets/
│   ├── fonts/
│   └── imgs/
├── android/
├── ios/
├── web/
├── test/
├── pubspec.yaml
└── LICENSE
```

## 프로젝트 인덱스

### 앱 진입점과 UI

- `lib/main.dart` - 애플리케이션 진입점, 전역 provider 설정, 앱 테마 생성, `MaterialApp` 구성.
- `lib/pages/home.dart` - `home/home_page.dart`의 barrel export.
- `lib/pages/home/home_page.dart` - 메인 화면, 데이터 로딩(FutureBuilder 체인), 공지 확인, AppBar·본문 조합.
- `lib/pages/home/home_app_bar.dart` - AppBar 구성 위젯: 끼니 전환 버튼(`MealOfDaySwitchButton`), 요일 탭바(`DayOfWeekTabBar`), 날짜 표시 제목(`AnimatedDateTitle`).
- `lib/pages/home/meal_card.dart` - 식당별 메뉴를 표시하는 카드 위젯(`MealCard`).
- `lib/pages/home/nested_page_scroll.dart` - 끼니 간 페이지 전환과 내부 콘텐츠 스크롤을 통합 처리하는 커스텀 스크롤 시스템(`NestedPageScrollController`, `NestedPageScrollView`, `NestedPageScrollControllerGroup`).
- `lib/pages/home/week_meal_view.dart` - 요일 탭뷰 및 반응형 카드 테이블 레이아웃(`WeekMealTabBarView`).
- `lib/pages/home_drawer.dart` - 드로어(사이드바), 공지 다이얼로그, 운영 시간 섹션, 문의 링크, 라이선스 진입점.

### 상태와 도메인 모델

- `lib/model.dart` - 공용 언어/테마 상태를 위한 `BapUModel`과 화면 로컬 선택 상태를 위한 `HomePageModel`.
- `lib/meal.dart` - `Meal`, `CafeteriaMeal`, `DayMeal`, `WeekMeal` 및 관련 enum 등 핵심 도메인 타입.
- `lib/i18n.dart` - 문자열 리소스에서 사용하는 최소한의 언어 추상화.
- `lib/string.dart` - 현지화된 표시 문자열과 날짜 포맷 헬퍼.

### 데이터, 캐싱, 플랫폼 분기

- `lib/api_v2.dart` - 식단 및 공지사항 원격 API 호출과 JSON → 모델 파싱.
- `lib/data.dart` - 현재 주차 기준 캐시 정책, 캐시 읽기 경로, fetch-and-cache 흐름.
- `lib/storage.dart` - 네이티브 또는 웹 저장 동작을 선택하는 조건부 export.
- `lib/storage_io.dart` - 네이티브 플랫폼용 파일 기반 캐시 구현.
- `lib/storage_web.dart` - 파일 캐시 대신 항상 새로 fetch 하도록 만드는 웹용 저장 stub.
- `lib/platform_http_client.dart` - 플랫폼별 HTTP 클라이언트 생성을 위한 조건부 export.
- `lib/platform_http_client_io.dart` - iOS의 Cupertino, Android의 Cronet HTTP 클라이언트 구현.
- `lib/platform_http_client_web.dart` - 웹용 HTTP 클라이언트 구현.

### 에셋과 테스트

- `assets/imgs/bapu_logo.svg` - 사이드바에 들어간 로고 이미지.
- `assets/fonts/` - Pretendard 폰트 파일과 번들된 라이선스 텍스트.
- `test/widget_test.dart` - 테스트(테스트로써 기능은 거의 없음)
