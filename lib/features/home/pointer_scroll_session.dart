import 'dart:async';

import 'package:flutter/widgets.dart';

/// 요일과 끼니가 공유하는 휠 세션. 대각선 입력의 작은 흔들림으로 축을 바꾸지 않는다.
class PointerScrollSession {
  static const singleIdleDuration = Duration(milliseconds: 180);
  static const burstIdleDuration = Duration(milliseconds: 90);

  Axis? _axis;
  bool _shifted = false;
  int _eventCount = 0;
  Timer? _timer;

  Axis? get axis => _axis;

  Axis peekAxis(Offset delta, {required bool shifted}) =>
      _axis ??
      (shifted || delta.dx.abs() > delta.dy.abs()
          ? Axis.horizontal
          : Axis.vertical);

  double horizontalDelta(Offset delta, {required bool shifted}) =>
      (_axis == null ? shifted : _shifted) && delta.dy.abs() > delta.dx.abs()
      ? delta.dy
      : delta.dx;

  void record(
    VoidCallback onIdle, {
    required Axis axis,
    bool shifted = false,
    bool boundary = false,
  }) {
    // resolver가 선택한 입력만 축을 잠그고 만료 타이머를 함께 등록한다.
    if (_axis == null) {
      _axis = axis;
      _shifted = shifted;
    }
    _eventCount++;
    _timer?.cancel();
    // 주 경계 진입은 관성 꼬리가 멎은 뒤 실행한다.
    _timer = Timer(
      boundary || _eventCount == 1 ? singleIdleDuration : burstIdleDuration,
      () {
        reset();
        onIdle();
      },
    );
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _axis = null;
    _eventCount = 0;
    _shifted = false;
  }
}
