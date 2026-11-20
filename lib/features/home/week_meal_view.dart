import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/app_info.dart';

import 'meal_page_grid.dart';
import 'nested_page_scroll.dart';
import 'resistant_page_motion.dart';
import 'pointer_scroll_session.dart';

export 'meal_page_grid.dart' show buildMealShareText;

class WeekMealTabBarView extends StatefulWidget {
  const WeekMealTabBarView({
    super.key,
    required this.weekMeal,
    required this.tabController,
    required this.pageControllerGroup,
    required this.pageCount,
    required this.onPageChanged,
    required this.appInfo,
    required this.mondayOfWeek,
    this.currentKstDateTime,
    this.onNextWeekRequested,
    this.onPreviousWeekRequested,
    this.isMealTransitionActive,
    this.onHorizontalActivityChanged,
  });

  final WeekMeal weekMeal;
  final TabController tabController;
  final NestedPageScrollControllerGroup pageControllerGroup;
  final int pageCount;
  final void Function(int) onPageChanged;
  final Future<AppInfo> appInfo;
  final DateTime mondayOfWeek;
  final DateTime? currentKstDateTime;
  final Future<void> Function()? onNextWeekRequested;
  final Future<void> Function()? onPreviousWeekRequested;
  final bool Function()? isMealTransitionActive;
  final ValueChanged<bool>? onHorizontalActivityChanged;

  @override
  State<WeekMealTabBarView> createState() => _WeekMealTabBarViewState();
}

class _WeekMealTabBarViewState extends State<WeekMealTabBarView>
    with SingleTickerProviderStateMixin {
  // 일반 페이지 이동과 별도로 관리하는 주 경계 전환 기준.
  static const _weekBoundaryDistance = 120.0;
  final _horizontalMotion = ResistantPageMotion();
  final _pointerSession = PointerScrollSession();
  final _edgeDistance = ValueNotifier<double>(0);
  late final AnimationController _edgeReturn;

  ScrollPosition? _horizontalPosition;
  ScrollPosition? _trackedHorizontalPosition;
  bool _horizontalActivity = false;
  bool _horizontalPointerScrolling = false;
  bool _horizontalTouchDragging = false;
  double? _touchReleasePixels;
  double? _settlingEdgeDirection;
  int _edgeHapticStep = 0;
  bool _edgeEligible = false;
  double _edgeDirection = 1;
  bool _weekRequestInProgress = false;

  @override
  void initState() {
    super.initState();
    _edgeReturn = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        _edgeDistance.value = _edgeReturn.value
            .clamp(0.0, double.infinity)
            .toDouble();
      });
    widget.tabController.addListener(_onTabChanged);
  }

  void _updateHorizontalActivity() {
    // 주 경계 표시만 복귀할 때는 버튼과 본문 모두 끼니 입력을 허용한다.
    final active =
        _horizontalPosition != null ||
        (_trackedHorizontalPosition?.isScrollingNotifier.value ?? false);
    if (_horizontalActivity == active) return;
    _horizontalActivity = active;
    widget.onHorizontalActivityChanged?.call(active);
  }

  void _trackHorizontalPosition(ScrollPosition position) {
    if (_trackedHorizontalPosition == position) return;
    _trackedHorizontalPosition?.isScrollingNotifier.removeListener(
      _updateHorizontalActivity,
    );
    _trackedHorizontalPosition = position;
    position.isScrollingNotifier.addListener(_updateHorizontalActivity);
  }

  void _onTabChanged() {
    if (widget.tabController.indexIsChanging) {
      _horizontalMotion.relinquish();
      _finishHorizontal(cancel: true);
      _pointerSession.reset();
    } else if (_edgeEligible) {
      final edgeIndex = _edgeDirection > 0
          ? widget.tabController.length - 1
          : 0;
      // 실제 선택 요일이 바뀐 뒤에는 같은 입력으로 주를 전환하지 않는다.
      if (widget.tabController.index != edgeIndex) {
        _edgeEligible = false;
        _edgeDistance.value = 0;
      }
    }
  }

  void _finishHorizontal({
    bool cancel = false,
    bool allowWeekChange = true,
    double velocity = 0,
  }) {
    // 무관한 취소나 중복 종료는 복귀 스프링과 재입력 기준을 바꾸지 않는다.
    if (!cancel && _horizontalPosition == null) return;
    final changeWeek =
        !cancel &&
        allowWeekChange &&
        _edgeEligible &&
        _edgeDistance.value >= _weekBoundaryDistance;
    final onWeekRequested = _edgeDirection > 0
        ? widget.onNextWeekRequested
        : widget.onPreviousWeekRequested;
    final position = _horizontalPosition;
    _touchReleasePixels = !cancel && _horizontalTouchDragging
        ? position?.pixels
        : null;
    _settlingEdgeDirection = null;
    final edgeVelocity = position == null || _horizontalPointerScrolling
        ? 0.0
        : _edgeDirection *
              (axisDirectionIsReversed(position.axisDirection)
                  ? velocity
                  : -velocity);
    _horizontalPosition = null;
    if (cancel) {
      _horizontalMotion.cancel();
    } else {
      _horizontalMotion.finish(velocity: velocity);
    }
    _horizontalPointerScrolling = false;
    _horizontalTouchDragging = false;
    _edgeEligible = false;
    _edgeReturn.stop();
    if (cancel) {
      _edgeDistance.value = 0;
    } else if (_edgeDistance.value > 0) {
      // 손을 놓은 위치와 속도에서 스크롤용 스프링으로 복귀한다.
      _edgeReturn.animateWith(
        ScrollSpringSimulation(
          const ScrollPhysics().spring,
          _edgeDistance.value,
          0,
          edgeVelocity,
        ),
      );
    }
    if (changeWeek && onWeekRequested != null) {
      unawaited(_changeWeek(onWeekRequested));
    }
    _updateHorizontalActivity();
  }

  Future<void> _changeWeek(Future<void> Function() changeWeek) async {
    // 요청 대기는 중복 진입만 막고 현재 식단의 입력 활동에는 포함하지 않는다.
    if (!mounted || _weekRequestInProgress) return;
    _weekRequestInProgress = true;
    try {
      await changeWeek();
    } finally {
      _weekRequestInProgress = false;
    }
  }

  void _beginHorizontal(
    ScrollPosition position, {
    bool touch = false,
    bool allowWeekBoundary = true,
  }) {
    // 경계로 정렬 중인 새 터치는 첫 입력의 방향을 확인한 뒤 진입을 허용한다.
    double? settlingEdgeDirection;
    final releasedPixels = _touchReleasePixels;
    if (touch &&
        !widget.tabController.indexIsChanging &&
        _horizontalMotion.isSettling &&
        releasedPixels != null) {
      final movement = position.pixels - releasedPixels;
      if (movement > 0 &&
          widget.onNextWeekRequested != null &&
          position.pixels >
              position.maxScrollExtent - position.viewportDimension) {
        settlingEdgeDirection = 1;
      } else if (movement < 0 &&
          widget.onPreviousWeekRequested != null &&
          position.pixels <
              position.minScrollExtent + position.viewportDimension) {
        settlingEdgeDirection = -1;
      }
    }
    // 같은 입력이나 휠 관성으로는 경계 도착 후에도 주를 전환하지 않는다.
    final atEnd =
        widget.onNextWeekRequested != null &&
        widget.tabController.index == widget.tabController.length - 1 &&
        (position.pixels - position.maxScrollExtent).abs() < 0.01;
    final atStart =
        widget.onPreviousWeekRequested != null &&
        widget.tabController.index == 0 &&
        (position.pixels - position.minScrollExtent).abs() < 0.01;
    final eligible =
        allowWeekBoundary &&
        !position.isScrollingNotifier.value &&
        !widget.tabController.indexIsChanging &&
        (atEnd || atStart);
    final direction = atStart ? -1.0 : 1.0;
    // 복귀 중 다시 잡으면 현재 당김 거리에서 이어간다.
    final remainingDistance = eligible && direction == _edgeDirection
        ? _edgeDistance.value
        : 0.0;
    _finishHorizontal(cancel: true);
    _trackHorizontalPosition(position);
    _horizontalPosition = position;
    _settlingEdgeDirection = settlingEdgeDirection;
    _edgeEligible = eligible;
    _edgeDirection = direction;
    _edgeDistance.value = remainingDistance;
    _edgeHapticStep = (remainingDistance / (_weekBoundaryDistance / 4))
        .floor()
        .clamp(0, 4);
    _updateHorizontalActivity();
  }

  void _startHorizontal(BuildContext context, DragStartDetails details) {
    if (widget.isMealTransitionActive?.call() ?? false) {
      return;
    }
    _pointerSession.reset();
    final position = Scrollable.maybeOf(
      context,
      axis: Axis.horizontal,
    )?.position;
    if (position != null) {
      PointerScrollSession.clearWeekPull(Navigator.maybeOf(context));
      _beginHorizontal(
        position,
        touch: details.kind == PointerDeviceKind.touch,
      );
      _horizontalTouchDragging = details.kind == PointerDeviceKind.touch;
    }
  }

  void _updateEdgeHaptic(double distance) {
    if (!_horizontalTouchDragging || _horizontalPointerScrolling) return;
    final step = (distance / (_weekBoundaryDistance / 4)).floor().clamp(0, 4);
    if (step <= _edgeHapticStep) return;
    // 되당김과 빠르게 건너뛴 단계는 재생하지 않는다.
    _edgeHapticStep = step;
    unawaited(
      step == 4
          ? HapticFeedback.lightImpact()
          : HapticFeedback.selectionClick(),
    );
  }

  void _updateHorizontal(DragUpdateDetails details) {
    final position = _horizontalPosition;
    if (position == null || (widget.isMealTransitionActive?.call() ?? false)) {
      return;
    }
    final input = axisDirectionIsReversed(position.axisDirection)
        ? details.delta.dx
        : -details.delta.dx;
    final settlingEdgeDirection = _settlingEdgeDirection;
    if (settlingEdgeDirection != null && input != 0) {
      _edgeEligible = input * settlingEdgeDirection > 0;
      _edgeDirection = settlingEdgeDirection;
      _settlingEdgeDirection = null;
    }
    final boundary = _edgeDirection > 0
        ? position.maxScrollExtent
        : position.minScrollExtent;
    final atBoundary = (position.pixels - boundary).abs() < 0.01;
    var remainingDetails = details;
    if (_edgeEligible && (_edgeDistance.value > 0 || atBoundary)) {
      // 같은 요일의 경계로 돌아오면 일반 이동을 끝내고 다시 당길 수 있다.
      _horizontalMotion.cancel();
      final previous = _edgeDistance.value;
      final distance = (previous + input * _edgeDirection)
          .clamp(0.0, _weekBoundaryDistance * 2)
          .toDouble();
      _edgeDistance.value = distance;
      _updateEdgeHaptic(distance);
      if (distance > 0) return;
      final remaining = input + previous * _edgeDirection;
      if (remaining == 0) return;
      final dx = axisDirectionIsReversed(position.axisDirection)
          ? remaining
          : -remaining;
      remainingDetails = DragUpdateDetails(
        kind: details.kind,
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(dx, 0),
        primaryDelta: dx,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      );
    }
    final previousPixels = position.pixels;
    _horizontalMotion.update(
      position,
      remainingDetails,
      pointerScrolling: _horizontalPointerScrolling,
    );
    if (_edgeEligible &&
        !atBoundary &&
        input * _edgeDirection > 0 &&
        (position.pixels - boundary).abs() < 0.01) {
      // 경계까지 이동하는 데 쓴 거리를 빼고 남은 드래그만 당김에 반영한다.
      _horizontalMotion.cancel();
      _edgeDistance.value =
          ((input - (boundary - previousPixels)) * _edgeDirection)
              .clamp(0.0, _weekBoundaryDistance * 2)
              .toDouble();
      _updateEdgeHaptic(_edgeDistance.value);
    }
  }

  WheelScrollTarget? _wheelTargetFor(Axis axis, ScrollPosition? position) {
    if (!mounted ||
        widget.tabController.indexIsChanging ||
        (widget.isMealTransitionActive?.call() ?? false)) {
      return null;
    }
    if (axis == Axis.vertical) {
      return widget.pageControllerGroup
          .getController(widget.tabController.index)
          .wheelTarget;
    }
    if (position == null || !position.hasPixels) return null;
    return WheelScrollTarget(
      motion: _horizontalMotion,
      move: (details, allowWeekBoundary) {
        if (_horizontalPosition != position) {
          _beginHorizontal(position, allowWeekBoundary: allowWeekBoundary);
        }
        _horizontalPointerScrolling = true;
        _updateHorizontal(details);
      },
      finish: (allowWeekChange) =>
          _finishHorizontal(allowWeekChange: allowWeekChange),
      isWeekBoundary: () => _edgeEligible,
      // 휠에는 손을 뗐다는 이벤트가 없어 게이지가 찬 방향을 세션에 알려 준다.
      // 터치스크린에서는 게이지가 차도 손을 떼기 전까지 당김 거리를 줄일 수 있다.
      fullWeekPullDirection: () =>
          _edgeEligible && _edgeDistance.value >= _weekBoundaryDistance
          ? (axisDirectionIsReversed(position.axisDirection)
                ? -_edgeDirection
                : _edgeDirection)
          : 0,
      isWeekEdgePage: (position, page) =>
          (widget.onNextWeekRequested != null &&
              page == widget.tabController.length - 1) ||
          (widget.onPreviousWeekRequested != null && page == 0),
    );
  }

  @override
  void didUpdateWidget(WeekMealTabBarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController ||
        oldWidget.pageControllerGroup != widget.pageControllerGroup ||
        oldWidget.mondayOfWeek != widget.mondayOfWeek) {
      _pointerSession.reset();
    }
    if (oldWidget.tabController != widget.tabController) {
      _finishHorizontal(cancel: true);
      oldWidget.tabController.removeListener(_onTabChanged);
      widget.tabController.addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    _finishHorizontal(cancel: true);
    _trackedHorizontalPosition?.isScrollingNotifier.removeListener(
      _updateHorizontalActivity,
    );
    if (_horizontalActivity) widget.onHorizontalActivityChanged?.call(false);
    _pointerSession.reset();
    _edgeReturn.dispose();
    _edgeDistance.dispose();
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 먼 요일 탭의 비인접 전환은 TabBarView에 맡기고 본문 입력만 직접 조정한다.
    final pages = TabBarView(
      controller: widget.tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        widget.tabController.length,
        (tabIndex) => NestedPageScrollView(
          pointerSession: _pointerSession,
          isHorizontalInputActive: () => _horizontalPosition != null,
          wheelTargetFor: _wheelTargetFor,
          onHorizontalDragStart: _startHorizontal,
          onHorizontalDragUpdate: _updateHorizontal,
          onHorizontalDragEnd: (details) =>
              _finishHorizontal(velocity: details.primaryVelocity ?? 0),
          onHorizontalDragCancel: () =>
              _finishHorizontal(allowWeekChange: false),
          controller: widget.pageControllerGroup.getController(tabIndex),
          onPageChanged: (page) {
            // 비활성 요일의 동기화나 늦은 정렬이 끼니 버튼을 덮어쓰지 않게 한다.
            if (widget.tabController.index == tabIndex) {
              widget.onPageChanged(page);
            }
          },
          builder: (context, pageIndex) => MealPageGrid(
            meal: widget.weekMeal
                .fromDayOfWeek(DayOfWeek.values[tabIndex])
                .fromMealOfDay(MealOfDay.values[pageIndex]),
            mealOfDay: MealOfDay.values[pageIndex],
            targetDate: DateUtils.dateOnly(widget.mondayOfWeek)
                .add(Duration(days: tabIndex)),
            appInfo: widget.appInfo,
            currentKstDateTime: widget.currentKstDateTime,
          ),
        ),
        growable: false,
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: _edgeDistance,
      child: pages,
      builder: (context, distance, child) {
        final progress = (distance / _weekBoundaryDistance).clamp(0.0, 1.0);
        final offset = distance / (1 + distance / 80);
        final direction = Directionality.of(context) == TextDirection.rtl
            ? 1.0
            : -1.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (distance > 0)
              Align(
                alignment: _edgeDirection > 0
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(
                    label: _edgeDirection > 0
                        ? l10n.nextWeekPreview
                        : MaterialLocalizations.of(context).backButtonTooltip,
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(value: progress),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(direction * _edgeDirection * offset, 0),
              child: child,
            ),
          ],
        );
      },
    );
  }
}
