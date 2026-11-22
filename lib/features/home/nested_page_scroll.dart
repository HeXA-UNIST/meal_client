import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'resistant_page_motion.dart';
import 'pointer_scroll_session.dart';

/// 끼니(아침/점심/저녁) 페이지 전환을 담당하는 PageController.
///
/// 스크롤 방향에 따라 각 페이지의 [reverse] 상태를 관리하여,
/// 위로 스크롤해서 이전 페이지로 갈 때는 해당 페이지의 하단이,
/// 아래로 스크롤해서 다음 페이지로 갈 때는 상단이 먼저 보이도록 한다.
class NestedPageScrollController extends PageController {
  final int pageCount;
  final List<bool> _reverseList;

  // 버튼 이동은 진행 중인 사용자 입력과 별도의 요청이다.
  int navigationRevision = 0;
  WheelScrollTarget? wheelTarget;
  VoidCallback? _cancelWheel;
  ScrollPosition? Function()? _activeInnerPosition;

  /// 현재 선택된 끼니 페이지 내부 스크롤 위치. 키보드 스크롤에서 사용한다.
  ScrollPosition? get activeInnerPosition => _activeInnerPosition?.call();

  void cancelUserInput({bool keepWeekWheel = false}) {
    if (!keepWeekWheel) _cancelWheel?.call();
    navigationRevision++;
    notifyListeners();
  }

  void _prepareButtonMove() {
    _cancelWheel?.call();
    navigationRevision++;
    final currentPage = page!.round();
    _reverseList.fillRange(0, currentPage, false);
    _reverseList.fillRange(currentPage + 1, pageCount, false);
    notifyListeners();
  }

  NestedPageScrollController({
    super.initialPage,
    super.keepPage,
    super.viewportFraction,
    super.onAttach,
    super.onDetach,
    required this.pageCount,
  }) : _reverseList = List.generate(pageCount, (page) => page < initialPage);

  bool pageReversed(int page) => _reverseList[page];

  void outerScrollStart(int pageIndex) {
    _reverseList.fillRange(0, pageIndex, true);
    _reverseList.fillRange(pageIndex + 1, pageCount, false);
    notifyListeners();
  }

  @override
  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) {
    _prepareButtonMove();
    return super.animateToPage(page, duration: duration, curve: curve);
  }
}

/// 끼니 페이지와 콘텐츠를 별도로 유지하며 세로 입력을 조정한다.
/// 터치와 pan/zoom 트랙패드는 Flutter 드래그 인식을 사용하고,
/// 포인터 스크롤은 resolver로 가로 요일 스크롤과 소유권을 나눈다.
class NestedPageScrollView extends StatefulWidget {
  const NestedPageScrollView({
    super.key,
    required this.controller,
    required this.onPageChanged,
    required this.builder,
    this.pointerSession,
    this.isHorizontalInputActive,
    this.wheelTargetFor,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onHorizontalDragCancel,
  });

  final PointerScrollSession? pointerSession;
  final bool Function()? isHorizontalInputActive;
  final NestedPageScrollController controller;
  final void Function(int page) onPageChanged;
  final Widget Function(BuildContext context, int pageIndex) builder;
  final WheelScrollTarget? Function(Axis, ScrollPosition?)? wheelTargetFor;

  final void Function(BuildContext, DragStartDetails)? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragCancelCallback? onHorizontalDragCancel;

  @override
  State<NestedPageScrollView> createState() => _NestedPageScrollViewState();
}

class _NestedPageScrollViewState extends State<NestedPageScrollView>
    with AutomaticKeepAliveClientMixin {
  static const _edgeTolerance = 0.01;
  final _pageMotion = ResistantPageMotion();

  @override
  bool get wantKeepAlive => true;
  late final List<ScrollController> scrollControllers;
  Drag? _drag;
  ScrollController? _dragController;
  final _localPointerSession = PointerScrollSession();
  PointerScrollSession get _pointerSession =>
      widget.pointerSession ?? _localPointerSession;
  late int _navigationRevision;
  bool _pointerScrolling = false;
  bool _touchScrolling = false;
  bool _semanticScrolling = false;
  bool _horizontalDragging = false;
  int? _dragPointer;
  double _deferredDy = 0;
  int _inputEpoch = 0;
  bool _deferredUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _navigationRevision = widget.controller.navigationRevision;
    widget.controller.addListener(_onControllerChanged);
    widget.controller.wheelTarget = _wheelTarget;
    widget.controller._cancelWheel = _pointerSession.reset;
    widget.controller._activeInnerPosition = _currentInnerPosition;
    scrollControllers = List.generate(
      widget.controller.pageCount,
      (_) => ScrollController(),
      growable: false,
    );
  }

  ScrollPosition? _currentInnerPosition() {
    if (!mounted ||
        !widget.controller.hasClients ||
        _touchScrolling ||
        _pointerScrolling ||
        _pageMotion.isInputActive ||
        _pageMotion.isSettling ||
        widget.controller.position.isScrollingNotifier.value) {
      return null;
    }
    final page = widget.controller.page;
    if (page == null) return null;
    final index = page.round().clamp(0, scrollControllers.length - 1);
    if ((page - index).abs() * widget.controller.position.viewportDimension >=
            _edgeTolerance ||
        !_innerReady(index)) {
      return null;
    }
    return scrollControllers[index].position;
  }

  void _onControllerChanged() {
    if (_navigationRevision == widget.controller.navigationRevision) return;
    _navigationRevision = widget.controller.navigationRevision;
    _finish(cancel: true);
  }

  // 진입 방향에 따라 이전 끼니의 하단/다음 끼니의 상단을 준비한다.
  void _preparePages(int page) {
    widget.controller.outerScrollStart(page);
    for (var i = 0; i < scrollControllers.length; i++) {
      final controller = scrollControllers[i];
      if (i != page && controller.hasClients) controller.jumpTo(0);
    }
  }

  // 입력 세션이 끝나도 가로 정렬 활동은 계속될 수 있다.
  // 부모 ScrollPosition의 실제 활동 상태를 확인해 요일 확정 전 세로 이동을 막는다.
  bool get _horizontalScrolling =>
      (widget.isHorizontalInputActive?.call() ?? false) ||
      (Scrollable.maybeOf(
            context,
            axis: Axis.horizontal,
          )?.position.isScrollingNotifier.value ??
          false);

  void _start(DragStartDetails details) {
    _pointerSession.reset();
    _finish(cancel: true);
    if (!widget.controller.hasClients || _horizontalScrolling) return;
    PointerScrollSession.clearWeekPull(Navigator.maybeOf(context));
    _touchScrolling = true;
    // 시맨틱 스크롤 액션은 포인터 종류 없이 한 번에 큰 delta를 전달한다.
    _semanticScrolling = details.kind == null;
    _preparePages(widget.controller.page!.round());
  }

  void _useController(ScrollController controller, DragUpdateDetails details) {
    if (_dragController == controller && _drag != null) return;
    _drag?.cancel();
    _dragController = controller;
    _drag = controller.position.drag(
      DragStartDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
        kind: _pointerScrolling ? PointerDeviceKind.trackpad : null,
      ),
      () {
        _drag = null;
        _dragController = null;
      },
    );
  }

  void _move(
    ScrollController controller,
    double dy,
    DragUpdateDetails details,
  ) {
    _useController(controller, details);
    _drag?.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(0, dy),
        primaryDelta: dy,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  // reverse 변경/인접 페이지 배치가 끝난 다음 프레임에 남은 입력을 전달한다.
  void _defer(double dy, DragUpdateDetails details) {
    _deferredDy += dy;
    if (_deferredUpdateScheduled) return;
    _deferredUpdateScheduled = true;
    final epoch = _inputEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _inputEpoch) return;
      _deferredUpdateScheduled = false;
      final pending = _deferredDy;
      _deferredDy = 0;
      _update(
        DragUpdateDetails(
          kind: details.kind,
          sourceTimeStamp: details.sourceTimeStamp,
          delta: Offset(0, pending),
          primaryDelta: pending,
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
        ),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// 남은 입력 거리를 내부 콘텐츠와 페이지 이동에 배분한다.
  void _update(DragUpdateDetails details) {
    if (_horizontalScrolling) {
      _finish(cancel: true);
      return;
    }
    if ((!_touchScrolling && !_pointerScrolling) ||
        !widget.controller.hasClients) {
      return;
    }
    if (_pageMotion.isInputActive) {
      final remaining = _pageMotion.releaseAtOrigin(details);
      if (remaining == null) {
        _pageMotion.update(
          widget.controller.position,
          details,
          pointerScrolling: _pointerScrolling,
        );
        return;
      }
      details = remaining;
    }
    var remaining = details.delta.dy + _deferredDy;
    _deferredDy = 0;
    if (remaining.abs() < _edgeTolerance) return;
    final page = widget.controller.page!;
    final index = page.round().clamp(0, scrollControllers.length - 1);
    final aligned =
        (page - index).abs() <
        _edgeTolerance / widget.controller.position.viewportDimension;
    final inner = scrollControllers[index];
    if (aligned && !_innerReady(index)) {
      _defer(remaining, details);
      return;
    }
    if (aligned && inner.hasClients) {
      final position = inner.position;
      final reversed = widget.controller.pageReversed(index);
      final offsetDirection = reversed ? remaining : -remaining;
      final available = offsetDirection > 0
          ? position.maxScrollExtent - position.pixels
          : position.pixels - position.minScrollExtent;
      if (available > _edgeTolerance) {
        final consumed = remaining.clamp(-available, available).toDouble();
        _move(inner, consumed, details);
        remaining -= consumed;
        // 시맨틱 스크롤이 본문 끝을 넘겨 같은 액션에서 다음 끼니로 건너뛰지 않게 한다.
        if (_semanticScrolling || remaining.abs() < _edgeTolerance) return;
      }
    }

    _drag?.cancel();
    _drag = null;
    _dragController = null;
    _pageMotion.update(
      widget.controller.position,
      DragUpdateDetails(
        kind: details.kind,
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(0, remaining),
        primaryDelta: remaining,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
      pointerScrolling: _pointerScrolling,
    );
    return;
  }

  void _finish({DragEndDetails? details, bool cancel = false}) {
    // 마지막 입력이 레이아웃을 기다리는 중이면 거리를 소비한 뒤 종료한다.
    if (!cancel && _deferredDy != 0) {
      final epoch = _inputEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && epoch == _inputEpoch) _finish(details: details);
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _inputEpoch++;
    _deferredDy = 0;
    _deferredUpdateScheduled = false;
    final drag = _drag;
    _drag = null;
    _dragController = null;
    _pointerScrolling = false;
    _touchScrolling = false;
    _semanticScrolling = false;
    if (cancel) {
      drag?.cancel();
      _pageMotion.cancel();
    } else {
      final velocity = details?.primaryVelocity ?? 0;
      _pageMotion.finish(velocity: velocity);
      // 콘텐츠 내부의 관성은 Flutter에 맡긴다.
      drag?.end(
        DragEndDetails(
          velocity: Velocity(pixelsPerSecond: Offset(0, velocity)),
          primaryVelocity: velocity,
        ),
      );
    }
  }

  late final _wheelTarget = WheelScrollTarget(
    motion: _pageMotion,
    move: (details, _) {
      if (!mounted || !widget.controller.hasClients || _horizontalScrolling) {
        if (_pointerScrolling) _finish(cancel: true);
        return;
      }
      if (!_pointerScrolling) {
        _finish(cancel: true);
        _pointerScrolling = true;
        _preparePages(widget.controller.page!.round());
      }
      _update(details);
    },
    finish: (_) {
      if (mounted && _pointerScrolling) _finish();
    },
    readyForWheel: () {
      if (!mounted || !widget.controller.hasClients) return true;
      final page = widget.controller.page;
      if (page == null) return false;
      final index = page.round();
      if ((page - index).abs() * widget.controller.position.viewportDimension >=
          _edgeTolerance) {
        return true;
      }
      return _innerReady(index);
    },
    canRead: _canRead,
  );

  bool _innerReady(int index) {
    final inner = scrollControllers[index];
    return inner.hasClients &&
        axisDirectionIsReversed(inner.position.axisDirection) ==
            widget.controller.pageReversed(index);
  }

  bool _canRead(double delta) {
    if (!mounted || !widget.controller.hasClients) return false;
    final page = widget.controller.page;
    if (page == null ||
        (page - page.round()).abs() *
                widget.controller.position.viewportDimension >
            _edgeTolerance) {
      return false;
    }
    final inner = scrollControllers[page.round()];
    if (!inner.hasClients || !inner.position.hasContentDimensions) return false;
    final position = inner.position;
    final reversed = widget.controller.pageReversed(page.round());
    if (axisDirectionIsReversed(position.axisDirection) != reversed) {
      return false;
    }
    final next = position.pixels + (reversed ? -delta : delta);
    return next >= position.minScrollExtent && next <= position.maxScrollExtent;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollInertiaCancelEvent) {
      _pointerSession.reset(clearWeekPullIn: Navigator.maybeOf(context));
      return;
    }
    if (event is! PointerScrollEvent ||
        _touchScrolling ||
        _horizontalDragging ||
        event.scrollDelta == Offset.zero) {
      return;
    }
    final shifted = HardwareKeyboard.instance.isShiftPressed;
    final horizontal = Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position;
    final route = widget.wheelTargetFor;
    final controller = widget.controller;
    final session = _pointerSession;
    WheelScrollTarget? targetFor(Axis axis) {
      if (!mounted ||
          widget.controller != controller ||
          _pointerSession != session) {
        return null;
      }
      if (route != null) return route(axis, horizontal);
      return axis == Axis.vertical ? _wheelTarget : null;
    }

    final axis = _pointerSession.peekAxis(event.scrollDelta, shifted: shifted);
    if (axis == Axis.horizontal &&
        (horizontal == null || !horizontal.hasPixels || route == null)) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !widget.controller.hasClients) return;
      event.respond(allowPlatformDefault: false);
      _pointerSession.accept(
        event,
        shifted: shifted,
        targetFor: targetFor,
        navigator: Navigator.maybeOf(context),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final view = Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: (event) => _dragPointer ??= event.pointer,
      onPointerUp: (event) {
        if (_dragPointer == event.pointer) _dragPointer = null;
      },
      // 인식된 드래그의 PointerCancel도 onEnd로 전달될 수 있어 먼저 취소한다.
      onPointerCancel: (event) {
        if (_dragPointer != event.pointer) return;
        _dragPointer = null;
        if (_horizontalDragging) {
          _horizontalDragging = false;
          widget.onHorizontalDragCancel?.call();
        }
        if (_touchScrolling) _finish();
      },
      child: GestureDetector(
        onHorizontalDragStart: widget.onHorizontalDragStart == null
            ? null
            : (details) {
                _horizontalDragging = true;
                widget.onHorizontalDragStart!(context, details);
              },
        onHorizontalDragUpdate: widget.onHorizontalDragUpdate,
        onHorizontalDragEnd: widget.onHorizontalDragEnd == null
            ? null
            : (details) {
                if (!_horizontalDragging) return;
                _horizontalDragging = false;
                widget.onHorizontalDragEnd?.call(details);
              },
        onHorizontalDragCancel: widget.onHorizontalDragCancel == null
            ? null
            : () {
                if (!_horizontalDragging) return;
                _horizontalDragging = false;
                widget.onHorizontalDragCancel?.call();
              },
        onVerticalDragStart: _start,
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: (details) {
          if (_touchScrolling) _finish(details: details);
        },
        onVerticalDragCancel: () {
          if (_touchScrolling) _finish();
        },
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: widget.controller.pageCount,
          controller: widget.controller,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: widget.onPageChanged,
          itemBuilder: (context, pageIndex) => _KeptAliveItem(
            scrollController: scrollControllers[pageIndex],
            pageController: widget.controller,
            pageIndex: pageIndex,
            builder: widget.builder,
          ),
        ),
      ),
    );
    if (!kIsWeb) return view;
    // 웹에서 천천히 밀 때 식단이 손가락을 조금 더 일찍 따라오도록 한다.
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(gestureSettings: const DeviceGestureSettings(touchSlop: 12)),
      child: view,
    );
  }

  @override
  void didUpdateWidget(NestedPageScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.controller.pageCount == widget.controller.pageCount);
    if (oldWidget.pointerSession != widget.pointerSession ||
        oldWidget.controller != widget.controller) {
      // 세션을 여러 요일이 공유하므로 이전 뷰가 받던 휠 입력만 취소하고 분리한다.
      _finish(cancel: true);
      (oldWidget.pointerSession ?? _localPointerSession).detach(_wheelTarget);
      _unbindWheelTarget(oldWidget.controller);
      widget.controller.wheelTarget = _wheelTarget;
      widget.controller._cancelWheel = _pointerSession.reset;
      widget.controller._activeInnerPosition = _currentInnerPosition;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _navigationRevision = widget.controller.navigationRevision;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _unbindWheelTarget(NestedPageScrollController controller) {
    // 같은 컨트롤러에 새 뷰가 먼저 연결될 수 있다. 그때는 새 뷰의 콜백을 남겨 둔다.
    if (controller.wheelTarget != _wheelTarget) return;
    controller.wheelTarget = null;
    controller._cancelWheel = null;
    controller._activeInnerPosition = null;
  }

  @override
  void dispose() {
    // detach가 휠 종료 콜백을 호출할 수 있다. 짧은 당김을 먼저 취소해야 이미
    // 폐기된 자식 ScrollPosition에서 원위치로 돌아가는 애니메이션을 시작하지 않는다.
    _finish(cancel: true);
    _pointerSession.detach(_wheelTarget);
    _localPointerSession.reset();
    _unbindWheelTarget(widget.controller);
    widget.controller.removeListener(_onControllerChanged);
    for (final controller in scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

/// 끼니(아침/점심/저녁) 페이지 하나를 keep-alive로 유지하는 내부 위젯.
///
/// [AutomaticKeepAliveClientMixin]으로 오프스크린 상태에서도 엘리먼트를 살려두어,
/// 형제 탭의 sibling-sync [jumpToPage] 호출 시 기존 엘리먼트를 재사용한다.
/// 재빌드 없이 뷰포트만 이동하므로 [MealCard] 등 무거운 위젯 빌드 비용이 0이 된다.
///
/// [reverse] 변경([NestedPageScrollController.outerScrollStart] 등)은
/// 컨트롤러 리스너에서 감지해 [setState]로 반영한다.
/// [builder]가 교체되면([weekMeal] 갱신) [didUpdateWidget]에서 rebuild를 유도한다.
class _KeptAliveItem extends StatefulWidget {
  const _KeptAliveItem({
    required this.scrollController,
    required this.pageController,
    required this.pageIndex,
    required this.builder,
  });

  final ScrollController scrollController;
  final NestedPageScrollController pageController;
  final int pageIndex;
  final Widget Function(BuildContext, int) builder;

  @override
  State<_KeptAliveItem> createState() => _KeptAliveItemState();
}

class _KeptAliveItemState extends State<_KeptAliveItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late bool _reverse;

  @override
  void initState() {
    super.initState();
    _reverse = widget.pageController.pageReversed(widget.pageIndex);
    widget.pageController.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(_KeptAliveItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController.removeListener(_onControllerChanged);
      widget.pageController.addListener(_onControllerChanged);
      _reverse = widget.pageController.pageReversed(widget.pageIndex);
    }
  }

  void _onControllerChanged() {
    final next = widget.pageController.pageReversed(widget.pageIndex);
    if (next != _reverse) {
      setState(() => _reverse = next);
    }
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.vertical,
        controller: widget.scrollController,
        reverse: _reverse,
        physics: const _ImplicitOnlyScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: widget.builder(context, widget.pageIndex),
        ),
      ),
    );
  }
}

/// 포인터 드래그·휠은 상위 [NestedPageScrollView]에 맡기되,
/// 스크린 리더 순차 탐색의 자동 스크롤(`showOnScreen`)은 허용한다.
class _ImplicitOnlyScrollPhysics extends NeverScrollableScrollPhysics {
  const _ImplicitOnlyScrollPhysics({super.parent});

  @override
  _ImplicitOnlyScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ImplicitOnlyScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool get allowImplicitScrolling => true;
}

class NestedPageScrollControllerGroup {
  late final List<NestedPageScrollController> _controllers;
  int _page;
  int _activeIndex;
  // 그룹 주도 jumpToPage/animateToPage 실행 중 리스너 브로드캐스트를 억제한다.
  // 억제하지 않으면 비활성 탭의 jumpToPage가 활성 탭의 애니메이션을 취소한다.
  bool _isSyncing = false;

  NestedPageScrollControllerGroup({
    required int count,
    required int pageCount,
    int initialPage = 0,
    int? activeIndex,
  }) : _page = initialPage,
       _activeIndex = activeIndex ?? -1 {
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
        // 그룹 주도 동기화 중에는 브로드캐스트하지 않는다.
        // 억제하지 않으면 비활성 탭의 jumpToPage가 활성 탭의 애니메이션을 취소한다.
        if (_isSyncing || (_activeIndex >= 0 && index != _activeIndex)) {
          return;
        }
        final rounded = controller.page!.round();
        if (_page != rounded) {
          _page = rounded;
          // keep-alive로 살아있는 다른 탭의 컨트롤러도 즉시 동기화.
          // _isSyncing으로 jumpToPage가 유발하는 리스너 재진입을 차단한다.
          _isSyncing = true;
          for (final c in _controllers) {
            if (c == controller || !c.hasClients) continue;
            final siblingPage = c.page;
            if (siblingPage == null || siblingPage.round() != _page) {
              c.jumpToPage(_page);
            }
          }
          _isSyncing = false;
        }
      });

      return controller;
    }, growable: false);
  }

  // 요일 변경 뒤 이전 화면의 입력/관성이 새 끼니 상태를 덮어쓰지 않게 한다.
  void setActiveIndex(int index) {
    _activeIndex = index;
    _isSyncing = true;
    try {
      for (final controller in _controllers) {
        // 자동으로 도착한 요일에서 공유 휠 대기열을 이어 받는다.
        controller.cancelUserInput(keepWeekWheel: true);
        if (controller.hasClients) controller.jumpToPage(_page);
      }
    } finally {
      _isSyncing = false;
    }
  }

  NestedPageScrollController getController(int index) => _controllers[index];

  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
  }

  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
    // 현재 화면에 보이는 탭의 인덱스.
    // 이 탭의 컨트롤러만 애니메이션으로 이동하고,
    // 나머지 비활성 탭은 jumpToPage로 즉시 동기화하여
    // 불필요한 애니메이션 ticker 생성을 방지한다.
    int? activeIndex,
  }) async {
    // 로딩 중 아직 연결된 뷰가 없어도 이후 onAttach가 마지막 선택을 복원한다.
    _page = page;
    final futures = <Future<void>>[];

    // 비활성 탭의 jumpToPage가 리스너를 통해 활성 탭의 애니메이션을
    // 취소하지 않도록 for 루프 동안 브로드캐스트를 억제한다.
    _isSyncing = true;
    try {
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
          controller._prepareButtonMove();
          controller.jumpToPage(page);
        }
      }
      // jumpToPage 완료 후 억제 해제. 이후 활성 탭 애니메이션 리스너는 정상 동작.
    } finally {
      _isSyncing = false;
    }

    if (futures.isEmpty) {
      return;
    }

    await Future.wait(futures);
  }
}
