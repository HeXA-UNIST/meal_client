# Analytics 개인정보 수집 점검

점검일: 2026-10-06 (한국 시간). 대상: BapU의 접속 시간 및 주요 클릭 분석.
소스와 GA 속성 `bapu-efdc8`(527964534)의 관리 화면을 확인했다.
이 문서는 수집 범위 점검과 승인된 GA 설정 변경의 기록이며, 법적 적합성 판정을 의미하지 않는다.

## 앱에서 추가하는 데이터

`lib/core/analytics.dart`의 `ui_click` 이벤트는 아래 값만 추가한다.

| 매개변수 | 값 |
| --- | --- |
| `target` | `day_tab`, `meal_switch`, `next_week`, `operation_hours`, `settings`, `notification_settings` |
| `screen` | `home`, `next_week`, `settings` |
| `day_of_week` | 요일 탭에서만 `mon`~`sun` |
| `meal_of_day` | 식사 전환에서만 `breakfast`, `lunch`, `dinner` |

Analytics에 사용자 ID·사용자 속성을 지정하는 호출은 없다.
이메일, 학번, 알림 키워드, 알레르기 선택값, 식단 본문을 Analytics에 전달하는 경로도 찾지 못했다.
GA DebugView의 실제 알림 설정 클릭에서 `target=notification_settings`를 확인했다.
동일 이벤트의 매개변수 목록에는 위 앱 값 외에 SDK가 추가한 `debug_event`,
`firebase_event_origin`, `firebase_screen_class`, `firebase_screen_id`,
`ga_session_id`, `ga_session_number`가 표시됐다.
이 점검으로 모든 플랫폼의 모든 이벤트가 검증됐다고 볼 수는 없다.

## 자동 수집과 식별자

- 접속 분석용 `session_start`, 화면 조회 및 이용 시간 등의 기본 이벤트가 자동 수집된다.
- 앱은 SDK의 앱 인스턴스 ID, Web은 쿠키 기반 클라이언트 ID 등으로 이용을 구분한다.
  광고 식별자를 끄거나 앱에서 `setUserId`를 호출하지 않아도 이 식별자는 남는다.
  사용 횟수와 사용자 수를 측정하기 위한 가명 식별이며, 완전 익명 수집으로 표현하면 안 된다.
- OS·언어·기기·대략적 지역 등 SDK의 기본 정보가 추가될 수 있다.
- IP는 Google 서버와 통신할 때 전달된다. Google 문서에 따르면 GA4는 개별 IP를
  기록·저장하지 않지만, 이 사실이 IP가 전송되지 않는다는 뜻은 아니다.
  이 설명은 GA4에 관한 것이며 Firebase의 다른 서비스·운영 로그까지 확대하지 않는다.
- Web의 기본 페이지 조회에는 URL·페이지 제목·유입 URL 등이 포함될 수 있다.
  현재 앱 코드에는 개인정보를 URL에 넣는 경로가 없지만 외부에서 붙인 URL 쿼리까지
  모두 차단하는 코드나 GA 설정은 없다.

근거: [기본 수집과 앱 인스턴스 ID](https://support.google.com/firebase/answer/6318039),
[GA 개인정보 제어](https://support.google.com/analytics/answer/9019185),
[자동 이벤트](https://support.google.com/analytics/answer/9234069).

## 코드와 빌드 설정

| 항목 | 확인한 상태 | 검증 범위 |
| --- | --- | --- |
| iOS IDFA | 광고 식별자 없는 Analytics 사용 | CI와 README에 `FIREBASE_ANALYTICS_WITHOUT_ADID=true`; 플러그인의 SPM 선택 조건 확인. 이전 시뮬레이터 로그에서 IDFA 접근 불가 확인 |
| iOS IDFV | 수집 비활성화 | 소스와 최신 시뮬레이터 빌드의 `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED=false` 확인 |
| iOS 광고 활용 | 광고 저장·사용자 데이터·개인 최적화 기본 거부 | 소스와 최신 시뮬레이터 빌드의 Info.plist 확인 |
| Android 광고 식별자 | 수집 비활성화 및 광고 권한 제거 선언 | Manifest 소스 확인; 이번 점검에서 병합된 Release Manifest와 실기기 전송은 미검증 |
| Web 광고 활용 | 광고 저장·사용자 데이터·개인 최적화 기본 거부 | SDK 시작 전 `web/index.html`의 consent 기본값 확인 |

iOS의 광고 식별자 제외는 로컬 빌드에서도 환경변수를 지정해야 한다.
[Firebase 수집 제어](https://firebase.google.com/docs/analytics/ios/configure-data-collection).

## GA 관리 화면에서 확인한 상태

| 항목 | 저장된 값 | 판단 |
| --- | --- | --- |
| Google 신호 | 미활성화 (사용 설정 버튼 표시) | 추가적인 Google 계정 연결 분석을 사용하지 않음 |
| 광고 개인 최적화 | 307개 지역 중 0개 허용 | 유지 권장 |
| 세부 위치 및 기기 데이터 | 비활성 | 사용자 승인 후 전체 수집 스위치를 끄고 페이지 재진입으로 확인 |
| 이벤트 데이터 보관 | 2개월 | 현재 목적에 적합 |
| 사용자 데이터 보관 | 2개월 | 사용자 승인 후 14개월에서 변경하여 저장; 페이지 재진입으로 확인 |
| 새 사용자 활동 발생 시 재설정 | 비활성 | 사용자 승인 후 끄고 저장; 페이지 재진입으로 확인 |
| 계정 추가 데이터 공유 | 제품·서비스, 참여 모델링·통계, 기술 지원, 비즈니스 추천 모두 비활성 | 유지 권장; 계정 전체에 적용되는 설정 |
| Google Ads / Display & Video 360 / Search Ads 360 | 연결 0건 | 확인한 광고 제품 연계 없음 |
| BigQuery | 연결 없음 | 이 연결을 통한 원본 데이터 내보내기 없음 |
| Web 향상된 측정 | 비활성, 기본 페이지 조회 표시 | 유지 권장 |
| Web 이메일 데이터 수정 | 활성 | 유지 권장; 패턴 검출 방식이라 완전 차단 보장은 아님 |
| Web URL 쿼리 매개변수 수정 | 비활성 | 쿼리에 개인정보를 넣지 않도록 관리하고, 전송 전 제거 방안 검토 |
| Web 연결된 사이트 태그 | 0개 | 추가 연결 태그 없음 |

모든 제품 링크를 확인한 것은 아니다. 위 표에 명시한 연결만 점검했다.
[세부 위치·기기 수집](https://support.google.com/analytics/answer/12002752),
[데이터 보관](https://support.google.com/analytics/answer/7667196),
[Web 데이터 수정](https://support.google.com/analytics/answer/13544947).

## 적용한 변경과 영향

2026-10-06 16:23 (한국 시간)에 아래 설정의 저장 상태를 최종 확인했다.

1. 이 속성의 세부 위치·기기 수집을 비활성화했다.
   도시, 기기 모델·이름, 상세 OS 버전, 화면 해상도 등의 수집이 줄어든다.
   국가·지역 수준 정보와 기본 세션·클릭 분석은 남는다. 이미 수집한 데이터는 소급 삭제되지 않는다.
2. 사용자 데이터 보관을 14개월에서 2개월로 줄이고, 새 활동 시 재설정을 껐다.
   사용자 단위 장기 분석 가능 기간이 줄어든다. Google 문서상 보관 설정 변경은 24시간 후 적용되며,
   보관 기간을 넘긴 해당 데이터는 이후 정기 삭제 처리 대상이 된다.
   보관 설정은 표준 집계 보고서를 전부 삭제하거나 Google의 모든 보관 데이터를 없애는 설정이 아니다.

## 남은 검토 사항

Web에서 페이지 URL과 유입 URL의 쿼리·해시 등을 전송 전에 제거하는 방안을 검토한다.
현재 유출 사례를 확인한 것은 아니다. 적용 시 캠페인·유입 분석에 미칠 영향도 함께 결정한다.

이번 변경은 GA 속성 설정에만 적용했다. 앱 동작이나 Web URL 전송 코드는 변경하지 않았다.
Crashlytics 오류·스택 수집은 Analytics와 별도 경로이며 이 문서의 상세 점검 대상이 아니다.
