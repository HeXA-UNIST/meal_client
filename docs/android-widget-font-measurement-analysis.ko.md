# Android 위젯 텍스트 렌더링 개선

분석일: 2026-10-18. 수정 전 원인 분석과 현재 작업트리의 반영 상태를 함께 기록한다.

## 반영 상태

현재 작업트리에 `4ca4174`의 여백·부분 말줄임·전체 높이 측정·미리보기 12sp 측정 수정과
회귀 테스트를 반영했다. 줄 간격은 사용자 요청에 따라 실제 위젯과 미리보기 모두 기존
4sp를 유지한다. 실제 위젯·미리보기·권한 안내의 글꼴은 `sans-serif`로 통일했다.

Android 단위 테스트 31개와 디버그 APK 빌드를 통과했다. 수정 APK를 설치한 SM-S926N의
One UI 홈 화면에서 147×203dp와 230.25×203dp 위젯 모두 배추김치까지 6개 메뉴가 표시되고
상태 영역과 겹치지 않는 것을 확인했다. 설정 미리보기는 고정 180×180dp 안에서
넘치는 메뉴에 말줄임을 표시하는 것을 확인했다.

임시 실기기 Instrumentation으로 실제 렌더러를 사용해 한글·영문 × 글자 배율 1.0·2.0 ×
너비 147·230.25·313.5dp의 12개 조합을 검사했다. 앱 Context와 외부 호스트 Context에
RemoteViews를 적용했을 때 실제 폰트·줄 수·필요 높이가 일치했고, 표시 문자열은 메뉴 높이와
20줄 상한 안에 들어갔다. 2.0 배율은 진단용 Context 설정으로 검증했으며 시스템 설정 변경이나
실제 런처의 큰 글자 화면 검증을 대체하지 않는다. 임시 진단 소스와 테스트 APK는 정리했다.

아래 원인 분석과 과거 측정값은 수정 전 코드 `86fae17`을 기준으로 한다.

## 확정한 범위

Android 홈 위젯에서는 Pretendard를 사용하지 않고 시스템 글꼴을 사용한다.
일반 RemoteViews TextView를 유지하며, 실제 표시와 내부 측정·설정 미리보기의 조건을
일치시키고 메뉴 공간과 말줄임을 개선한다. Flutter 앱 본문의 폰트 변경은 범위에 포함하지 않는다.

## 결론

앱 내부 메뉴 측정에는 번들 Pretendard가 적용되지만, 외부 RemoteViews 적용에서는
기본 글꼴이 사용된다. 이 차이로 내부 측정에만 추가 줄바꿈이 발생하여, 실제 홈 화면에는
공간이 남아도 배추김치가 미리 제외된다.

현재 XML의 `android:fontFamily="@font/pretendard"` 지정은 앱 내부 측정과 미리보기에는
효과가 있지만, 확인한 홈 위젯 표시 경로에는 적용되지 않는다. Flutter 앱 본문의
Pretendard 적용 여부와는 별개다.

## 재현 환경과 관찰

- 기기: Samsung SM-S926N, Android 17 / API 37, One UI 버전 속성 `90000`.
- 화면: 1440×3120px, 적용 밀도 640dpi (`density=4.0`), 시스템 글자 배율 1.0.
- 코드: `experiment/home-widget`, HEAD `86fae17`의 디버그 앱.
- 비교 기준: 사용자 제공 5.1.1 스크린샷 및 현재 디버그 앱의 One UI 홈 화면.
- 메뉴: 쌀밥, 매콤순두부국, 순살치킨까스&어니언S, 미트소스스파게티, 양상추샐러드, 배추김치.

홈 화면의 좁은 위젯은 `양상추샐러드…`까지 표시하고 아래 공간이 남는다.
넓은 위젯은 배추김치까지 표시한다. `dumpsys appwidget`에서 두 위젯 크기는 각각
147×203dp와 230.25×203dp이며, 실제 메뉴 TextView 높이는 두 경우 모두 464px였다.
위젯 갱신 로그에도 배추김치를 포함한 6개 항목이 있어 데이터 누락은 배제했다.
두 너비 모두 2열 전환 기준인 250dp 미만이므로 1열 경로다.

## 실기기 측정 결과

임시 Instrumentation APK에서 설치된 앱의 레이아웃과 동일 메뉴를 사용했다.
헤더·메뉴·상태 크기를 각각 13sp·12sp·11sp로 맞추고, 상태는 `19:00 마감`으로 설정했다.
일반 앱 Context의 직접 inflate와, One UI 패키지 Context를 호스트로 한
`RemoteViews.apply`를 비교했다. 별도로 제한된 앱 Context의 직접 inflate도 확인했다.

아래의 외부 적용 값은 실기기에서 재현한 호스트 적용 경로의 값이다.
실행 중인 One UI 프로세스의 TextPaint를 직접 읽은 것은 아니다.
외부 적용의 배정 높이 464px는 홈 화면에서 읽은 실제 TextView 높이와 일치했다.

| 너비 | 측정 방식 | 메뉴 폭 | 배정 높이 | 필요 높이 | 줄 수 | 판정 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 147dp | 일반 앱 Context | 420px | 460px | 510px | 7 | 초과 |
| 147dp | 외부 RemoteViews 적용 | 420px | 464px | 430px | 6 | 전체 표시 가능 |
| 230.25dp | 일반 앱 Context | 753px | 460px | 436px | 6 | 전체 표시 가능 |
| 230.25dp | 외부 RemoteViews 적용 | 753px | 464px | 430px | 6 | 전체 표시 가능 |

좁은 위젯의 내부 측정에서만 다음처럼 마지막 `S`가 다음 줄로 넘어간다.

```text
순살치킨까스&어니언
S
```

외부 적용에서는 같은 메뉴가 한 줄이다. 내부 판정은 7줄에 필요한 510px가 배정된
460px를 넘는다고 판단해 마지막 항목을 제외한다. 실제 화면은 6줄이면 충분하지만,
이미 잘린 문자열을 받으므로 배추김치를 복구할 수 없다.
가로로 넓히면 내부 측정에서도 해당 메뉴가 한 줄에 들어가므로 배추김치가 나타난다.

## 폰트가 달라지는 이유와 근거

현재 측정 함수는 `LayoutInflater.from(context).inflate(...)`를 사용한다.
외부 RemoteViews는 다른 앱의 리소스를 불러올 때 `CONTEXT_RESTRICTED` 환경을 만든다.
확인한 Android SDK 소스의 TextView 구현은 제한된 Context에서 폰트 리소스 로딩을
건너뛰고 글꼴 이름 해석으로 넘어간다. 이 경로에서 앱의 Pretendard 폰트 파일이
실제 글꼴로 선택되지 않고 기본 글꼴로 대체된다. 사용자 권한 설정 문제가 아니다.

실기기에서 **실제 그리기에 쓰이는 `TextView.paint.typeface`**를 비교한 결과:

| 환경 | 제한된 Context | 번들 Pretendard와 일치 | 실제 폰트 굵기 |
| --- | --- | --- | ---: |
| 앱 내부 측정 | 아니요 | 예 | 500 |
| 외부 RemoteViews 적용 | 예 | 아니요 | 400 |
| 제한된 앱 Context 직접 inflate | 예 | 아니요 | 400 |

글자 크기 48px, letterSpacing -0.01, 줄 간격 추가 16px, 배율과 언어 설정은 같았다.
`TextView.typeface` 반환값만으로는 이 차이가 드러나지 않아 TextPaint를 기준으로 확인했다.

관련 코드와 공식 근거:

- [메뉴 측정·말줄임](../android/app/src/main/kotlin/pro/hexa/meal/meal_client/BapUWidgetDataHelper.kt):
  `truncateMenuByRealLayout`, `truncateMenuTwoColumnsByRealLayout`.
- [위젯 바인딩](../android/app/src/main/kotlin/pro/hexa/meal/meal_client/BapUWidget2x2Provider.kt):
  크기별 RemoteViews 생성과 측정용 `setup`.
- [위젯 XML](../android/app/src/main/res/layout/widget_2x2.xml),
  [폰트 리소스](../android/app/src/main/res/font/pretendard.xml).
- 로컬 Android SDK `sources/android-37.0/android/widget/RemoteViews.java`의
  외부 리소스 Context 생성과 `TextView.java`의 `TextAppearance_fontFamily` 처리.
- [Google Glance 공식 문서의 Handle text](https://developer.android.com/develop/ui/compose/glance/build-ui#handle-text)는
  시스템 글꼴을 지원하지만 앱의 커스텀 글꼴은 지원하지 않는다고 명시한다.
  우리 앱은 Glance를 사용하지 않으며, 이 문서는 위젯의 폰트 제약을 설명하는 보조 근거다.

## 최근 변경이 이번 증상에 미치는 영향

`develop`의 `4ca4174`는 줄 간격을 4sp에서 2sp로 줄이고, 여백과 영역 간격을 줄여
메뉴 높이를 10dp 더 확보한다. 마지막 항목의 부분 표시와 말줄임 처리도 개선한다.
이 커밋은 분석 당시 `experiment/home-widget`에는 포함되어 있지 않았다.

해당 여백과 줄 간격 변경을 실기기 진단 뷰에 동일하게 적용한 결과, 좁은 위젯은 다음과 같았다.

| 측정 방식 | 배정 높이 | 필요 높이 | 줄 수 |
| --- | ---: | ---: | ---: |
| 일반 앱 Context | 500px | 462px | 7 |
| 외부 RemoteViews 적용 | 504px | 390px | 6 |

이번 식단은 기존 내부 측정 방식에서도 전체가 들어간다. 따라서 최근 변경으로 이번
조기 말줄임은 완화될 수 있으나, 측정과 표시의 폰트 불일치 자체는 해결되지 않는다.
이는 진단 뷰에 치수를 적용한 결과이며 해당 커밋을 설치한 뒤 홈 화면에서 확인한 결과는 아니다.

## 후속 수정 방향과 검증 경계

1. 위젯 표시와 측정·미리보기에서 번들 폰트 참조를 제거하고 같은 시스템 글꼴을 사용한다.
   예를 들어 `sans-serif`를 명시할 수 있으며, 본문과 헤더의 굵기도 일치시킨다.
2. 1열·2열 모두 글자 크기, 자간, 줄 간격, 폰트 패딩, 언어·줄바꿈 조건을 실제 표시와 맞춘다.
   시스템 글꼴을 지정하는 것만으로 모든 측정 차이가 사라진다고 가정하지 않는다.
3. 런처가 전달한 크기로 기존 레이아웃 실측을 유지하고, 전체 텍스트의 필요 높이를 먼저 측정한 뒤
   표시 줄 수 상한을 별도로 검사한다. 줄 수 제한 때문에 필요 높이가 작게 측정되지 않게 한다.
4. 최근 변경의 여백·줄 간격 축소와 마지막 항목 부분 말줄임을 함께 검토한다.
   추가 공간 확보와 측정 불일치 수정은 각각 검증한다.
5. 우선 현재의 고정 12sp와 메뉴 생략 방식을 유지한다. 자동 크기 조절이나 기본 말줄임으로의
   전환은 아래 장단점을 참고할 수 있으나, 이번 기록만으로 도입을 결정하지 않는다.

수정 후 검증할 항목:

- 이번 6개 메뉴를 같은 높이의 147dp·230.25dp 너비에서 비교한다. 실제로 전체가 들어가는
  경우 불필요한 말줄임이 없어야 하며, 상태 영역과 겹치지 않아야 한다.
- 250dp 전후의 1열·2열 전환, 긴 한글·영문 메뉴, 한 항목의 여러 줄 표시를 확인한다.
- 기본·큰 글자 설정과 시스템 글꼴·굵게 설정 변경 시 내부 측정과 실제 표시를 비교한다.
- 설정 미리보기와 홈 위젯의 글꼴·크기·줄바꿈을 확인하고, 리사이즈 후 표시도 다시 확인한다.
- JVM 단위 테스트는 생략 문자열과 경계 로직을 검증하고, 실제 폰트와 줄바꿈은
  외부 RemoteViews 적용 및 런처 화면에서 검증한다.

이번 확인은 위 실기기와 현재 디버그 코드에 한정한다. 기존 5.1.1 태그에도 XML 폰트 지정은
있지만 과거 배포 APK를 다시 설치해 검증하지 않았으므로, 모든 과거 버전·OS·런처에서
동일하게 동작했다고 단정하지 않는다.

원인 분석 당시의 진단용 소스와 테스트 APK는 정리했다. 이후 수정 결과는 상단 반영 상태에 기록했다.

## 개선에 필요한 RemoteViews 텍스트 제약

조사 범위는 현재 사용하는 RemoteViews + 프레임워크 TextView다. 일반 Flutter/Compose 화면의
텍스트 기능을 그대로 사용할 수 있다고 보지 않는다. 아래 API 호출 제한은 로컬 API 37 소스에서
확인했으며, 원격 호출 가능 여부는 지원 대상 OS에서도 확인해야 한다.

### 사용할 수 있는 설정과 적용 범위

| 항목 | 가능한 방식 | 제약 |
| --- | --- | --- |
| 시스템 글꼴 | XML의 `fontFamily="sans-serif"`, `serif`, `monospace` 등 | 같은 이름이라도 제조사 글꼴과 한글·이모지 폴백까지 동일하다고 보장할 수 없음 |
| 굵게·기울임 | XML `textStyle`, 표준 `StyleSpan` | 실제 표시와 측정에 같은 설정을 적용해야 함 |
| 세부 굵기 | XML `textFontWeight` 등 플랫폼 설정 | 실제 선택된 시스템 글꼴의 지원 범위와 폴백에 영향받음 |
| 텍스트·색·크기 | `setTextViewText`, `setTextColor`, `setTextViewTextSize` | 크기 단위를 SP로 전달하면 호스트가 적용할 때 해당 환경에서 변환함 |
| 최대 줄 수 | XML `maxLines`, 원격 `setInt(..., "setMaxLines", ...)` | 높이에 들어가는 줄 수를 자동으로 의미하지 않음 |
| 자간·줄 간격·폰트 패딩 | XML `letterSpacing`, `lineSpacingExtra`, `includeFontPadding` 등 | 각 속성의 setter가 모두 원격 호출 가능한 것은 아님 |
| 줄바꿈·하이픈 | XML `breakStrategy`, `hyphenationFrequency` 등 | 언어·OS·폰트에 따라 줄바꿈과 필요 높이가 달라짐 |

일반 TextView의 public setter라고 해서 `RemoteViews.setInt/setFloat/setString`으로
모두 호출할 수 있는 것은 아니다. 프레임워크는 `@RemotableViewMethod`가 붙은 메서드만
허용한다. API 37 소스에서는 `setMaxLines`, `setLetterSpacing`은
허용되지만, `setTypeface`, `setTextAppearance`, `setEllipsize`, `setIncludeFontPadding`,
`setBreakStrategy`, `setHyphenationFrequency`, 자동 크기 조절 setter는 같은 방식으로
호출할 수 없다. `setLineSpacing(float, float)`도 일반 원격 setter로 직접 호출할 수 없다.
이런 속성은 XML로 지정하거나, 지원되는 대체 API와 레이아웃을 선택해야 한다.

- [RemoteViews API](https://developer.android.com/reference/android/widget/RemoteViews)
- [위젯에서 지원되는 뷰의 범위](https://developer.android.com/develop/ui/views/appwidgets#create-the-widget-layout)
- [TextView API와 XML 속성](https://developer.android.com/reference/android/widget/TextView)

### 자동 크기 조절과 말줄임

프레임워크 TextView의 XML `android:autoSizeTextType="uniform"`은 API 26부터 제공된다.
위젯에서도 XML 설정을 통해 호스트가 실제 배정 크기로 글자 크기를 선택하게 하는 방안은
검토할 수 있다. 다만 이번 기기에서 새로 적용해 검증한 것은 아니다.
최솟값·최댓값·후보 크기를 지정해야 하고, 공식 문서는 autosize와 `wrap_content` 조합에서
예상 밖 결과가 생길 수 있다고 설명한다. 앱의 “고정 12sp로 메뉴 항목 수를 줄인다”는 현재
동작을 바꾸므로 실제 도입 전 가독성과 표시 정책을 결정해야 한다.

XML `ellipsize="end"`는 실제 TextView 레이아웃에 맞춰 문자를 생략하는 기능이다.
`maxLines`가 2 이상일 때 `start`/`middle`은 지원되지 않는다. API 문서는 END/MARQUEE만
허용된다고 명시하지만, 여러 줄 메뉴가 스크롤된다는 보장은 아니므로 메뉴에는 END를 검토한다.
기본 말줄임은 메뉴 항목의 의미나 생략된 메뉴 개수를 알지 못한다.
앱에서 항목 전체를 제거하는 현재 정책과 동일한 동작은 아니다.

- [TextView 자동 크기 조절](https://developer.android.com/develop/ui/views/text-and-emoji/autosizing-textview)
- [TextView 말줄임](https://developer.android.com/reference/android/widget/TextView#setEllipsize(android.text.TextUtils.TruncateAt))

### 줄 간격과 접근성

하나의 TextView에 메뉴를 줄바꿈으로 합치면 `lineSpacingExtra`는 자동 줄바꿈에도,
메뉴 사이 줄바꿈에도 적용된다. 항목 사이만 넓히는 속성은 아니다. 이런 구분이 필요하면
항목별 뷰 등 별도 구조가 필요하지만 이번 문제 해결을 위해 바로 도입할 이유는 없다.

`includeFontPadding`은 글리프를 위한 위아래 여유, 줄 간격은 줄 사이 간격이며 서로 다르다.
폰트와 언어별 폴백의 높이가 달라질 수 있으므로, 글자 크기만으로 줄 높이를 추정하면 안 된다.

Android 14부터 최대 200%의 비선형 글자 배율을 지원한다. SP→PX를
`sp * scaledDensity`나 `sp * fontScale`로 직접 계산하면 정확하지 않을 수 있다.
`TypedValue.applyDimension` 또는 TextView의 SP 설정을 사용하고 실제 큰 글자 환경을 검증한다.
공식 문서는 `textSize`와 `lineHeight`를 모두 SP로 지정해야 비례 조정을 받을 수 있다고 설명한다.
자동 축소를 추가하면 시스템 큰 글자 설정의 목적과 충돌할 수 있다는 점도 제품 판단 대상이다.

- [Android 14 비선형 글자 배율 및 단위 변환](https://developer.android.com/about/versions/14/features#non-linear-font-scaling)

위 항목은 문서·소스 조사 결과이며, 자동 크기 조절이나 기본 말줄임을 새로 적용한
실기기 검증은 하지 않았다.
