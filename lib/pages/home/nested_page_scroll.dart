import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 끼니(아침/점심/저녁) 페이지 전환을 담당하는 PageController.
///
/// 스크롤 방향에 따라 각 페이지의 [reverse] 상태를 관리하여,
/// 위로 스크롤해서 이전 페이지로 갈 때는 해당 페이지의 하단이,
/// 아래로 스크롤해서 다음 페이지로 갈 때는 상단이 먼저 보이도록 한다.
class NestedPageScrollController extends PageController {
  final int pageCount;
  final List<bool> _reverseList;

  NestedPageScrollController({
    super.initialPage,
    super.keepPage,
    super.viewportFraction,
    super.onAttach,
    super.onDetach,
    required this.pageCount,
  }) : _reverseList = List.generate(
         pageCount,
         (page) => page < initialPage ? true : false,
       );

  bool pageReversed(int page) => _reverseList[page];

  void outerScrollStart(int pageIndex) {
    _reverseList.fillRange(0, pageIndex, true);
    if (pageIndex + 1 < pageCount) {
      // fillRange의 end는 exclusive이므로 pageCount를 사용해야
      // 마지막 페이지까지 올바르게 채워진다.
      _reverseList.fillRange(pageIndex + 1, pageCount, false);
    }
    notifyListeners();
  }

  @override
  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) {
    final currentPage = this.page!.round();
    _reverseList.fillRange(0, currentPage, false);
    if (currentPage + 1 < pageCount) {
      // fillRange의 end는 exclusive이므로 pageCount를 사용해야
      // 마지막 페이지까지 올바르게 채워진다.
      _reverseList.fillRange(currentPage + 1, pageCount, false);
    }
    notifyListeners();
    return super.animateToPage(page, duration: duration, curve: curve);
  }

  /// [outerScrollStart]로 reverse를 설정한 뒤 페이지를 전환한다.
  /// 스크롤 방향에 따라 이전 페이지의 하단/상단이 자연스럽게 보인다.
  Future<void> animateToPageFromScroll(
    int page, {
    required Duration duration,
    required Curve curve,
  }) {
    outerScrollStart(this.page!.round());
    return super.animateToPage(page, duration: duration, curve: curve);
  }
}

enum _CurrentlyScrolling { inner, outer }

/// 끼니(아침/점심/저녁) 간 페이지 전환과 각 페이지 내부 콘텐츠 스크롤을
/// 하나의 위젯에서 통합 처리하는 중첩 스크롤 뷰.
///
/// ## 스크롤 입력 처리 구조
///
/// 두 가지 입력 경로를 분리하여 각각 최적화된 방식으로 처리한다:
///
/// ### 1. 터치 드래그 (모바일, 터치스크린) — [GestureDetector]
/// - [onVerticalDragStart]: 드래그 시작 시 내부(콘텐츠) vs 외부(페이지) 중
///   어느 쪽을 스크롤할지 결정한다. 내부 콘텐츠가 스크롤 끝에 도달한 상태면
///   외부(페이지 전환)로, 아니면 내부 스크롤로 시작한다.
/// - [onVerticalDragUpdate]: 외부 스크롤 중 페이지 경계를 넘어
///   다음 페이지에 도달하면, 드래그를 내부 스크롤로 자연스럽게 전환하여
///   연속적인 스크롤 경험을 제공한다.
/// - [onVerticalDragEnd]: 드래그 종료 시 물리 시뮬레이션(fling)을 적용하고
///   상태를 정리한다.
///
/// ### 2. 포인터 스크롤 (마우스 휠, 터치패드) — [Listener.onPointerSignal]
/// - [_handlePointerScroll]에서 처리한다.
/// - 터치 드래그와 달리 연속적인 드래그 세션이 없으므로, 매 이벤트마다
///   독립적으로 내부 스크롤 여유분을 계산하여 내부/외부를 판단한다.
/// - 내부 스크롤 여유가 있으면 콘텐츠를 스크롤하고, 끝에 도달하면
///   페이지 전환 애니메이션을 실행한다.
/// - 페이지 전환 애니메이션 중에는 추가 입력을 무시하여
///   중복 전환을 방지한다 ([_isAnimatingPage]).
///
/// ### PageView의 NeverScrollableScrollPhysics
/// [PageView]와 내부 [SingleChildScrollView] 모두
/// [NeverScrollableScrollPhysics]를 사용하여 Flutter 기본 스크롤을 비활성화하고,
/// 위의 두 입력 경로가 스크롤을 완전히 제어한다.
class NestedPageScrollView extends StatefulWidget {
  const NestedPageScrollView({
    super.key,
    required this.controller,
    required this.onPageChanged,
    required this.builder,
  });

  final NestedPageScrollController controller;
  final void Function(int page) onPageChanged;
  final Widget Function(BuildContext context, int pageIndex) builder;

  @override
  State<NestedPageScrollView> createState() => _NestedPageScrollViewState();
}

class _NestedPageScrollViewState extends State<NestedPageScrollView> {
  late final List<ScrollController> scrollControllers;
  Drag? drag;
  int? currentPageIndex;
  double prevPage = 0;
  _CurrentlyScrolling? currentlyScrolling;
  bool _isAnimatingPage = false;

  @override
  void initState() {
    scrollControllers = List.generate(
      widget.controller.pageCount,
      (pageIndex) => ScrollController(),
      growable: false,
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handlePointerScroll(event);
        }
      },
      child: GestureDetector(
      onVerticalDragStart: (details) {
        final mediaQuery = MediaQuery.of(context);
        if (details.globalPosition.dy >=
            mediaQuery.size.height - mediaQuery.padding.bottom) {
          return;
        }

        currentPageIndex = widget.controller.page!.round();

        final scrollController = scrollControllers[currentPageIndex!];
        final ScrollController currentController;
        if (scrollController.position.atEdge) {
          currentlyScrolling = _CurrentlyScrolling.outer;
          currentController = widget.controller;

          widget.controller.outerScrollStart(currentPageIndex!);
          for (var c in scrollControllers) {
            if (c != scrollController && c.hasClients) {
              c.jumpTo(0);
            }
          }
        } else {
          currentlyScrolling = _CurrentlyScrolling.inner;
          currentController = scrollController;
        }

        drag = currentController.position.drag(details, () {});
        prevPage = widget.controller.page!;
      },
      onVerticalDragUpdate: (details) {
        if (drag == null) {
          return;
        }

        final scrollController = scrollControllers[currentPageIndex!];

        final double startScrollExtent;
        final double endScrollExtent;
        if (widget.controller.pageReversed(currentPageIndex!)) {
          startScrollExtent = scrollController.position.maxScrollExtent;
          endScrollExtent = scrollController.position.minScrollExtent;
        } else {
          startScrollExtent = scrollController.position.minScrollExtent;
          endScrollExtent = scrollController.position.maxScrollExtent;
        }

        final currentPage = widget.controller.page!;
        final middlePage = ((currentPage + prevPage) / 2).round();

        if (currentlyScrolling == _CurrentlyScrolling.outer &&
            startScrollExtent != endScrollExtent &&
            ((scrollController.position.pixels == startScrollExtent &&
                    details.delta.direction < 0) ||
                (scrollController.position.pixels == endScrollExtent &&
                    details.delta.direction > 0)) &&
            ((prevPage <= middlePage && middlePage <= currentPage) ||
                (currentPage <= middlePage && middlePage <= prevPage))) {
          drag?.cancel();

          currentlyScrolling = _CurrentlyScrolling.inner;
          drag = scrollController.position.drag(
            DragStartDetails(
              globalPosition: details.globalPosition,
              localPosition: details.localPosition,
            ),
            () {},
          );
        }

        drag?.update(details);
        prevPage = currentPage;
      },
      onVerticalDragEnd: (details) {
        drag?.end(details);
        drag = null;
        currentPageIndex = null;
        currentlyScrolling = null;
      },
      child: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: widget.controller.pageCount,
        controller: widget.controller,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: widget.onPageChanged,
        itemBuilder: (BuildContext context, int pageIndex) {
          return LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.vertical,
              controller: scrollControllers[pageIndex],
              reverse: widget.controller.pageReversed(pageIndex),
              physics: const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: widget.builder(context, pageIndex),
                ),
              ),
            ),
          );
        },
      ),
    ),
    );
  }

  @override
  void dispose() {
    for (final controller in scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 마우스 휠·터치패드의 [PointerScrollEvent]를 처리한다.
  ///
  /// 터치 드래그([GestureDetector])와 달리 연속적인 세션이 없으므로,
  /// 매 이벤트마다 현재 페이지의 내부 스크롤 잔여량을 계산하여
  /// 콘텐츠 스크롤과 페이지 전환 중 어느 동작을 수행할지 독립적으로 결정한다.
  void _handlePointerScroll(PointerScrollEvent event) {
    final dy = event.scrollDelta.dy;
    if (dy == 0 || _isAnimatingPage) return;

    final pageIndex = widget.controller.page!.round();
    final sc = scrollControllers[pageIndex];
    final reversed = widget.controller.pageReversed(pageIndex);

    final double scrollableRemaining;
    if (dy > 0) {
      // 아래로 스크롤
      scrollableRemaining = reversed
          ? sc.position.pixels - sc.position.minScrollExtent
          : sc.position.maxScrollExtent - sc.position.pixels;
    } else {
      // 위로 스크롤
      scrollableRemaining = reversed
          ? sc.position.maxScrollExtent - sc.position.pixels
          : sc.position.pixels - sc.position.minScrollExtent;
    }

    if (scrollableRemaining > 0) {
      // 내부 스크롤 여유 있음
      final clampedDy = dy.clamp(-scrollableRemaining, scrollableRemaining);
      sc.jumpTo(sc.offset + (reversed ? -clampedDy : clampedDy));
    } else {
      // 내부 끝 → 페이지(끼니) 전환
      final int targetPage;
      if (dy > 0 && pageIndex < widget.controller.pageCount - 1) {
        targetPage = pageIndex + 1;
      } else if (dy < 0 && pageIndex > 0) {
        targetPage = pageIndex - 1;
      } else {
        return;
      }
      // 터치 드래그와 동일하게 다른 페이지의 내부 스크롤을 리셋
      for (var c in scrollControllers) {
        if (c != sc && c.hasClients) {
          c.jumpTo(0);
        }
      }
      _isAnimatingPage = true;
      widget.controller
          .animateToPageFromScroll(
            targetPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          )
          .then((_) => _isAnimatingPage = false);
    }
  }
}

class NestedPageScrollControllerGroup extends ChangeNotifier {
  late final List<NestedPageScrollController> _controllers;
  int _page;

  NestedPageScrollControllerGroup({
    required int count,
    required int pageCount,
    int initialPage = 0,
  }) : _page = initialPage {
    _controllers = List.generate(count, (index) {
      final controller = NestedPageScrollController(
        initialPage: initialPage,
        onAttach: (position) {
          _controllers[index].jumpToPage(_page);
        },
        pageCount: pageCount,
      );

      // 매 스크롤 픽셀마다 호출되지만, 실제로 rounded 값이
      // 바뀔 때만 대입하여 불필요한 연산을 줄인다.
      controller.addListener(() {
        final rounded = controller.page!.round();
        if (_page != rounded) {
          _page = rounded;
        }
      });

      return controller;
    }, growable: false);
  }

  NestedPageScrollController getController(int index) => _controllers[index];

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }

    super.dispose();
  }

  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Cubic curve,
    // 현재 화면에 보이는 탭의 인덱스.
    // 이 탭의 컨트롤러만 애니메이션으로 이동하고,
    // 나머지 비활성 탭은 jumpToPage로 즉시 동기화하여
    // 불필요한 애니메이션 ticker 생성을 방지한다.
    int? activeIndex,
  }) async {
    final futures = <Future<void>>[];

    for (int i = 0; i < _controllers.length; i++) {
      final controller = _controllers[i];
      if (!controller.hasClients) continue;

      if (activeIndex == null || i == activeIndex) {
        // 현재 보이는 탭의 애니메이션 완료 시점을 기다린다.
        futures.add(
          controller.animateToPage(page, duration: duration, curve: curve),
        );
      } else {
        // 비활성 탭: 화면에 보이지 않으므로 즉시 이동 (ticker 낭비 없음)
        controller.jumpToPage(page);
      }
    }

    if (futures.isEmpty) {
      return;
    }

    await Future.wait(futures);
  }
}
