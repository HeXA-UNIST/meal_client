# `nested_page_scroll.dart` 분석 리포트

---

## 목차

1. [개요](#1-개요)
2. [클래스별 상세 설명](#2-클래스별-상세-설명)
3. [상태 머신 분석](#3-상태-머신-분석)

---

## 1. 개요

`nested_page_scroll.dart`는 BapU 앱의 "아침/점심/저녁" 끼니 전환 스크롤을 담당하는 **커스텀 중첩 스크롤 시스템**이다.

Flutter 기본 `NestedScrollView`는 사용하지 않고, `PageView`와 `SingleChildScrollView`를 **수동으로 조합**하여 다음 두 가지 동작을 하나의 제스처 흐름으로 통합한다:

- **내부 스크롤**: 한 끼니 페이지 안에서 콘텐츠를 위아래로 스크롤
- **페이지 전환**: 내부 스크롤이 끝에 도달하면 다음/이전 끼니로 전환

핵심 UX 목표는 **방향 연속성**이다. 아래로 스크롤해서 다음 페이지로 넘어가면 그 페이지의 상단이 먼저 보이고, 위로 스크롤해서 이전 페이지로 돌아가면 그 페이지의 하단이 먼저 보여야 한다. 이를 `SingleChildScrollView.reverse` 프로퍼티를 동적으로 제어하여 구현한다.

입력 경로는 두 가지다:

| 경로 | 위젯 | 특징 |
|------|------|------|
| 터치 드래그 | `GestureDetector` | 연속 세션, 수동 `Drag` 핸드오버 |
| 마우스 휠 / 터치패드 | `Listener.onPointerSignal` | 이벤트 단위, 락(`_isAnimatingPage`) 기반 |

---

## 2. 클래스별 상세 설명

### 2.1 `NestedPageScrollController`

```dart
class NestedPageScrollController extends PageController {
  final int pageCount;
  final List<bool> _reverseList;
```

`PageController`를 확장한 클래스로, 각 페이지의 **`reverse` 상태 테이블**을 관리한다.

#### `_reverseList`란?

`_reverseList[i] == true`이면 페이지 `i`의 `SingleChildScrollView`가 역방향(`reverse: true`)으로 렌더링된다. 즉 콘텐츠를 하단부터 보여주는 상태다.

이것이 방향 연속성의 핵심 트릭이다:
- 위로 스크롤해서 이전 페이지(인덱스 `i`)로 가면 → `_reverseList[i] = true` → 페이지 하단이 먼저 보임 ✓
- 아래로 스크롤해서 다음 페이지(인덱스 `i`)로 가면 → `_reverseList[i] = false` → 페이지 상단이 먼저 보임 ✓

#### 주요 메서드

| 메서드 | 역할 | `_reverseList` 변화 |
|--------|------|---------------------|
| `outerScrollStart(pageIndex)` | 터치 드래그로 페이지 전환 시작 시 호출 | `0..pageIndex-1` → `true`, `pageIndex+1..end` → `false` |
| `animateToPage(page)` | 프로그래매틱 페이지 이동 (탭 전환 등) | `0..currentPage-1` → `false`, `currentPage+1..end` → `false` |
| `animateToPageFromScroll(page)` | 마우스 휠로 페이지 전환 시 호출 | `outerScrollStart` 위임 후 `super.animateToPage` |

#### 초기화 로직

```dart
_reverseList = List.generate(
  pageCount,
  (page) => page < initialPage,
);
```

`initialPage`가 1이면 `[true, false, false]`로 시작한다. 이미 "아래에서" 시작한 페이지들은 역방향 상태로 초기화한다.

---

### 2.2 `NestedPageScrollView`

실제 UI와 이벤트 처리를 담당하는 `StatefulWidget`.

#### 상태 변수

```dart
late final List<ScrollController> scrollControllers; // 페이지별 내부 스크롤 컨트롤러
Drag? drag;                          // 현재 활성 드래그 세션
int? currentPageIndex;               // 드래그 중인 페이지 인덱스
double prevPage = 0;                 // 직전 프레임의 PageView 위치
_CurrentlyScrolling? currentlyScrolling; // 내부/외부 스크롤 모드
bool _isAnimatingPage = false;       // 마우스 휠 페이지 전환 애니메이션 락
```

#### 입력 처리 구조

```
Listener (PointerScrollEvent)
  └─ _handlePointerScroll()

GestureDetector (터치)
  ├─ onVerticalDragStart  → 스크롤 소유권 결정
  ├─ onVerticalDragUpdate → 소유권 이전 가능
  └─ onVerticalDragEnd    → 상태 정리
```

`PageView`와 `SingleChildScrollView` 모두 `NeverScrollableScrollPhysics`를 사용해 Flutter 기본 스크롤을 **완전히 비활성화**하고, 위 두 경로가 `ScrollPosition.drag()`를 직접 제어한다.

#### 핵심: 수동 `Drag` 핸드오버

`onVerticalDragStart`에서 `currentController.position.drag(details, () {})`로 드래그 세션을 수동으로 시작한다. Flutter의 제스처 아레나를 우회하여 어느 `ScrollPosition`이 드래그를 소유할지 강제 결정하는 방식이다.

내부 콘텐츠가 스크롤 끝에 닿으면 `onVerticalDragUpdate` 도중 기존 `drag.cancel()`하고 새 `Drag`를 생성해 소유권을 이전한다.

---

### 2.3 `NestedPageScrollControllerGroup`

여러 탭이 존재할 때(예: 요일별 탭) 각 탭의 `NestedPageScrollController`를 **동기화**하는 그룹 컨트롤러.

```dart
class NestedPageScrollControllerGroup {
  late final List<NestedPageScrollController> _controllers;
  int _page; // 그룹 전체의 현재 페이지
```

#### `animateToPage` 최적화

```dart
if (activeIndex == null || i == activeIndex) {
  futures.add(controller.animateToPage(...)); // 현재 보이는 탭만 애니메이션
} else {
  controller.jumpToPage(page); // 나머지는 즉시 이동 (ticker 낭비 방지)
}
```

비활성 탭을 `jumpToPage`로 즉시 동기화하여 불필요한 `AnimationController` 생성을 피한다.

---

## 3. 상태 머신 분석

### 3.1 터치 드래그 상태 머신

`_NestedPageScrollViewState`의 핵심 상태는 `currentlyScrolling`이 나타낸다:

```
┌───────────────────────────────────────────────────────────┐
│                        IDLE                               │
│  drag = null, currentlyScrolling = null                   │
└──────────────┬────────────────────────────────────────────┘
               │ onVerticalDragStart
               │
       ┌───────┴────────────────────────────────┐
       │ atEdge == true                          │ atEdge == false
       ▼                                         ▼
┌──────────────────────┐               ┌──────────────────────┐
│   SCROLLING_OUTER    │               │   SCROLLING_INNER    │
│ drag = PageController│               │ drag = innerController│
│ currentlyScrolling   │               │ currentlyScrolling   │
│   = .outer           │               │   = .inner           │
└──────┬───────────────┘               └──────────────────────┘
       │ onVerticalDragUpdate                    ▲
       │ (핸드오버 조건 충족)                     │
       │                                         │
       │ drag?.cancel()                          │
       └─────────────────────────────────────────┘
               (outer → inner 전환)
               
               onVerticalDragEnd (양쪽 공통)
               ──────────────────────────────→ IDLE
```

#### 상태 전이 표

| 현재 상태 | 이벤트 | 전이 조건 | 다음 상태 |
|-----------|--------|-----------|-----------|
| `IDLE` | `onVerticalDragStart` | `scrollController.position.atEdge == true` | `SCROLLING_OUTER` |
| `IDLE` | `onVerticalDragStart` | `scrollController.position.atEdge == false` | `SCROLLING_INNER` |
| `SCROLLING_OUTER` | `onVerticalDragUpdate` | 페이지 경계 통과 + 스크롤 가능 + 방향 일치 | `SCROLLING_INNER` |
| `SCROLLING_INNER` | `onVerticalDragUpdate` | (전이 없음) | `SCROLLING_INNER` |
| `SCROLLING_INNER` | `onVerticalDragEnd` | — | `IDLE` |
| `SCROLLING_OUTER` | `onVerticalDragEnd` | — | `IDLE` |

> **주의**: `SCROLLING_INNER → SCROLLING_OUTER` 전이는 **없다**. 드래그 중에 내부에서 외부로 전환하는 경로가 없다.

---

### 3.2 마우스 휠 결정 트리

터치 드래그와 달리 "세션" 개념이 없어 매 이벤트마다 독립 판단한다:

```
PointerScrollEvent 발생 (dy != 0)
│
├─ _isAnimatingPage == true → 무시 (early return)
│
└─ scrollableRemaining 계산
    │
    ├─ remaining > 0
    │   └─ sc.jumpTo(...) → 내부 스크롤
    │
    └─ remaining == 0
        ├─ _isAnimatingPage = true
        ├─ animateToPageFromScroll(targetPage)
        └─ .whenComplete() → _isAnimatingPage = false
```

`_isAnimatingPage` 플래그가 이 결정 트리의 유일한 외부 상태다.

---

### 3.3 `_reverseList` 상태 머신

`NestedPageScrollController` 내부의 `_reverseList`는 별도의 상태를 가진다:

```
초기화: page < initialPage → true, 나머지 → false

outerScrollStart(p):
  [0..p-1] = true   (위에서 내려오는 페이지들)
  [p+1..end] = false (아래에서 올라오는 페이지들)

animateToPage(targetPage):
  현재 currentPage 기준으로
  [0..currentPage-1] = false
  [currentPage+1..end] = false
  → currentPage 자신은 변경 없음
```
