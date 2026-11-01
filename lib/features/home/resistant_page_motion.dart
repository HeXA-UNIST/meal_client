import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// 축에 관계없이 페이지 경계의 저항과 전환을 관리한다.
/// 드래그는 손을 놓을 때 물리로 정렬하고, 휠은 저항 뒤 즉시 전환한다.
class ResistantPageMotion {
  // 가로·세로 휠 공통 조절값. 거리는 논리 픽셀이다.
  // 저항 계수는 작을수록 덜 뻑뻑하다. 0은 저항 없음, 1은 이전 강도다.
  static const resistanceCoefficient = 0.75;
  // 같은 계수에서 이 길이가 클수록 저항이 더 천천히 커진다.
  static const resistanceLength = 120.0;
  // 저항이 적용되기 전의 입력 누적 거리로 전환을 결정한다.
  static const commitDistance = 72.0;
  static const transitionDuration = Duration(milliseconds: 300);
  ScrollPosition? _position;
  Drag? _drag;
  double _origin = 0;
  double _startPixels = 0;
  ScrollPosition? _settlingPosition;
  double _distance = 0;
  double? _target;
  double _reverseDistance = 0;
  double _direction = 0;
  bool _pointerScrolling = false;

  // 입력 종료와 페이지 정렬 완료를 구분한다.
  bool get isInputActive => _position != null;
  bool get isSettling =>
      (_settlingPosition?.context.notificationContext?.mounted ?? false) &&
      _settlingPosition!.isScrollingNotifier.value;

  void update(
    ScrollPosition position,
    DragUpdateDetails details, {
    required bool pointerScrolling,
  }) {
    if (_position != position) {
      cancel();
      _position = position;
      _startPixels = position.pixels;
      _pointerScrolling = pointerScrolling;
      _origin = (position.pixels / position.viewportDimension).roundToDouble();
    }
    final reversed = axisDirectionIsReversed(position.axisDirection);
    final delta = position.axis == Axis.vertical
        ? details.delta.dy
        : details.delta.dx;
    final input = reversed ? delta : -delta;
    if (_target != null) {
      // 같은 제스처의 관성 꼬리로 여러 페이지를 건너뛰지 않는다.
      // 방향을 되돌리는 명시적인 입력은 전환 중에도 받아들인다.
      _reverseDistance = input * _direction < 0
          ? _reverseDistance + input.abs()
          : 0;
      if (_reverseDistance >= commitDistance) {
        final previous = _target!;
        _origin = previous;
        _commit(previous - _direction);
      }
      return;
    }
    _distance += input;
    if (!_pointerScrolling) {
      // 드래그는 페이지 사이에서 손가락을 직접 따라간다.
      _distance = _distance.clamp(
        -position.viewportDimension,
        position.viewportDimension,
      );
    }
    final startPage = _startPixels / position.viewportDimension;
    final target =
        (_distance > 0 ? startPage.floor() + 1 : startPage.ceil() - 1)
            .toDouble()
            .clamp(
              position.minScrollExtent / position.viewportDimension,
              position.maxScrollExtent / position.viewportDimension,
            );
    if ((_startPixels <= position.minScrollExtent && _distance < 0) ||
        (_startPixels >= position.maxScrollExtent && _distance > 0)) {
      _distance = 0;
    }
    // 더 당길수록 같은 입력에 대한 화면 이동량이 작아진다.
    final displayed = _pointerScrolling
        ? _distance /
              (1 + resistanceCoefficient * _distance.abs() / resistanceLength)
        : _distance;
    // 정렬 중 다시 잡아도 가장 가까운 페이지로 순간 이동하지 않는다.
    final pixels = (_startPixels + displayed)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final offset = pixels - position.pixels;
    _drag ??= position.drag(
      DragStartDetails(
        kind: PointerDeviceKind.trackpad,
        sourceTimeStamp: details.sourceTimeStamp,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
      () => _drag = null,
    );
    final dragOffset = reversed ? offset : -offset;
    _drag?.update(
      DragUpdateDetails(
        sourceTimeStamp: details.sourceTimeStamp,
        delta: position.axis == Axis.vertical
            ? Offset(0, dragOffset)
            : Offset(dragOffset, 0),
        primaryDelta: dragOffset,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
    if (_pointerScrolling && _distance.abs() >= commitDistance) {
      _commit(target);
    }
  }

  void _commit(double target) {
    final position = _position!;
    _direction = (target * position.viewportDimension - position.pixels).sign;
    if (_direction == 0) _direction = (target - _origin).sign;
    _target = target;
    _reverseDistance = 0;
    _animateTo(target * position.viewportDimension);
  }

  void finish({double velocity = 0}) {
    final position = _position;
    if (position == null) return;
    if (!_pointerScrolling) {
      // 종료 속도와 현재 위치를 그대로 Flutter의 페이지 물리에 전달한다.
      final drag = _drag;
      drag?.end(
        DragEndDetails(
          velocity: Velocity(
            pixelsPerSecond: position.axis == Axis.vertical
                ? Offset(0, velocity)
                : Offset(velocity, 0),
          ),
          primaryVelocity: velocity,
        ),
      );
      _trackSettling(position);
      _clear();
      return;
    }
    if (_target == null) {
      _animateTo(_origin * position.viewportDimension);
    }
    _clear();
  }

  void _animateTo(double pixels) {
    final position = _position!;
    // 기본 animateTo는 자식의 포인터 입력을 막으므로 관성 입력과 반전을
    // 계속 받을 수 있는 동일한 Flutter 애니메이션 활동을 사용한다.
    position.beginActivity(
      _InteractivePageActivity(
        position as ScrollActivityDelegate,
        from: position.pixels,
        to: pixels,
        duration: transitionDuration,
        // 원 코드와 같은 곡선으로 휠 전환을 예측 가능하게 유지한다.
        curve: Curves.easeOutQuad,
        vsync: position.context.vsync,
      ),
    );
    _trackSettling(position);
    _drag = null;
  }

  void _trackSettling(ScrollPosition position) {
    _stopTracking();
    if (!position.isScrollingNotifier.value) return;
    _settlingPosition = position;
    position.isScrollingNotifier.addListener(_onActivityChanged);
  }

  void _onActivityChanged() {
    if (!(_settlingPosition?.isScrollingNotifier.value ?? false)) {
      _stopTracking();
    }
  }

  void _stopTracking() {
    _settlingPosition?.isScrollingNotifier.removeListener(_onActivityChanged);
    _settlingPosition = null;
  }

  void cancel() {
    _drag?.cancel();
    final position = _position ?? (isSettling ? _settlingPosition : null);
    _stopTracking();
    if (position?.context.notificationContext?.mounted ?? false) {
      position!.hold(() {});
    }
    _clear();
  }

  void _clear() {
    _drag = null;
    _position = null;
    _distance = 0;
    _target = null;
    _reverseDistance = 0;
    _direction = 0;
    _pointerScrolling = false;
  }
}

/// 전환 중에도 뷰포트 안의 휠과 새 제스처를 받을 수 있게 한다.
class _InteractivePageActivity extends DrivenScrollActivity {
  _InteractivePageActivity(
    super.delegate, {
    required super.from,
    required super.to,
    required super.duration,
    required super.curve,
    required super.vsync,
  });

  @override
  bool get shouldIgnorePointer => false;
}
