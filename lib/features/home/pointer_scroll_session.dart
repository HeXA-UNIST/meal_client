import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'resistant_page_motion.dart';

/// 재생 시점에 선택된 요일 또는 끼니가 제공하는 입력 경로.
class WheelScrollTarget {
  const WheelScrollTarget({
    required this.motion,
    required this.move,
    required this.finish,
    this.readyForWheel,
    this.canRead,
    this.isWeekBoundary,
    this.fullWeekPullDirection,
    this.isWeekEdgePage,
  });

  final ResistantPageMotion motion;
  final void Function(DragUpdateDetails details, bool allowWeekBoundary) move;
  final void Function(bool allowWeekChange) finish;
  final bool Function()? readyForWheel;
  final bool Function(double delta)? canRead;
  final bool Function()? isWeekBoundary;
  final double Function()? fullWeekPullDirection;
  final bool Function(ScrollPosition position, double page)? isWeekEdgePage;
}

typedef _Sample = ({
  Duration time,
  double delta,
  PointerScrollEvent event,
  bool shifted,
});

sealed class _WheelDecision {
  const _WheelDecision();
}

final class _ContinueGroup extends _WheelDecision {
  const _ContinueGroup();
}

final class _Restart extends _WheelDecision {
  const _Restart(this.axis, this.samples);
  final Axis axis;
  final List<_Sample> samples;
}

final class _ReverseAlignment extends _WheelDecision {
  const _ReverseAlignment(this.page);
  final double page;
}

typedef WheelTargetForAxis = WheelScrollTarget? Function(Axis axis);

// 같은 Navigator에서 미리보기를 열거나 닫아도 남은 관성으로 도착 요일을 넘기지 않는다.
class _WeekPullTail {
  _WeekPullTail(_Sample first, this.count)
    : samples = [first],
      start = first.time;
  final List<_Sample> samples;
  final Duration start;
  int count;
  bool previousWasSpacedStep = false;

  List<PointerScrollEvent> resume(PointerScrollEvent event, bool shifted) {
    final last = samples.last;
    final delta = PointerScrollSession._component(
      event.scrollDelta,
      Axis.horizontal,
      shifted,
    );
    final gap = event.timeStamp - last.time;
    final quiet = count >= 3
        ? PointerScrollSession._guardDuration
        : PointerScrollSession.singleIdleDuration;
    if (event.device != last.event.device ||
        shifted != last.shifted ||
        gap.isNegative ||
        gap >= quiet ||
        delta * last.delta <= 0 ||
        (!shifted &&
            event.scrollDelta.dy.abs() >= 3 * math.max(1, delta.abs()))) {
      return [event];
    }
    // 늦게 도착한 휠 한 칸은 트랙패드의 마지막 관성 값일 수도 있다.
    // 보호가 남은 동안 220ms마다 한 칸씩 돌리면 첫 칸은 판정에만 쓰고 두 번째 칸부터 전달한다.
    final spacedStep =
        gap >= PointerScrollSession.singleIdleDuration &&
        ResistantPageMotion.isMouseWheelStep(event.kind, delta);
    if (spacedStep && previousWasSpacedStep) return [event];
    previousWasSpacedStep = spacedStep;
    count++;
    samples.removeWhere(
      (s) => event.timeStamp - s.time > const Duration(milliseconds: 136),
    );
    samples.add((
      time: event.timeStamp,
      delta: delta,
      event: event,
      shifted: shifted,
    ));
    // 새로 가속한 두 이벤트는 도착 화면의 입력으로 함께 전달한다.
    if (event.timeStamp - start >= PointerScrollSession.singleIdleDuration &&
        PointerScrollSession._accelerated(samples, delta.sign)) {
      return [last.event, event];
    }
    return const [];
  }
}

class _WheelGroup {
  _WheelGroup(this.axis, this.shifted, this.targetFor, this.queued);

  final Axis axis;
  final bool shifted;
  final WheelTargetForAxis targetFor;
  final bool queued;
  late bool waiting = queued;
  final pending = Queue<_Sample>();
  final history = <_Sample>[];
  final cross = <_Sample>[];
  int count = 0;
  bool closed = false;
  bool softRead = false;
  bool weekEdge = false;
  bool previousSampleSettled = false;
  NavigatorState? weekPullScope;
  WheelScrollTarget? target;
  ScrollPosition? position;
  double page = 0;
  double direction = 0;
  double reverse = 0;
  Duration committed = Duration.zero;
}

/// resolver가 선택한 원본 입력만 분류한다. 정렬 대기열과 관성 이력은
/// 드래그 소유권과 별도로 두어 짧은 idle 뒤에도 구별할 수 있게 한다.
class PointerScrollSession {
  static const singleIdleDuration = Duration(milliseconds: 180);
  static const burstIdleDuration = Duration(milliseconds: 90);
  static const _guardDuration = Duration(milliseconds: 380);
  static const _pairGap = Duration(milliseconds: 40);
  static const _crossWindow = Duration(milliseconds: 80);
  static final _weekPullTails = Expando<_WeekPullTail>();

  final _queue = Queue<_WheelGroup>();
  _WheelGroup? _current;
  _WheelGroup? _settlingGroup;
  bool _layoutRetryScheduled = false;
  Timer? _idle;
  Timer? _guard;
  int _generation = 0;

  Axis? get axis => _current?.closed == false ? _current?.axis : null;

  Axis peekAxis(Offset delta, {required bool shifted}) {
    final group = _current;
    if (group != null && (!group.closed || group.shifted == shifted)) {
      return group.axis;
    }
    return _dominant(delta, shifted);
  }

  static Axis _dominant(Offset delta, bool shifted) =>
      shifted || delta.dx.abs() > delta.dy.abs()
      ? Axis.horizontal
      : Axis.vertical;

  static double _component(Offset delta, Axis axis, bool shifted) =>
      axis == Axis.vertical || (shifted && delta.dy.abs() > delta.dx.abs())
      ? delta.dy
      : delta.dx;

  void accept(
    PointerScrollEvent event, {
    required bool shifted,
    required WheelTargetForAxis targetFor,
    required NavigatorState? navigator,
  }) {
    final tail = navigator == null ? null : _weekPullTails[navigator];
    if (tail == null) {
      _accept(event, shifted: shifted, targetFor: targetFor);
    } else {
      final next = tail.resume(event, shifted);
      if (next.isEmpty) return;
      _weekPullTails[navigator!] = null;
      for (final sample in next) {
        _accept(sample, shifted: shifted, targetFor: targetFor);
      }
    }
    final group = _current;
    if (navigator == null ||
        group == null ||
        group.closed ||
        group.axis != Axis.horizontal) {
      return;
    }
    final direction = group.target?.fullWeekPullDirection?.call() ?? 0;
    final value = _component(event.scrollDelta, Axis.horizontal, group.shifted);
    if (direction * value > 0) {
      // 게이지가 차면 같은 방향의 관성이 종료 타이머를 계속 미루지 않게 한다.
      // 손을 되돌려 당기는 입력은 타이머가 끝나기 전에도 받을 수 있다.
      group.weekPullScope = navigator;
      _weekPullTails[navigator] = _WeekPullTail((
        time: event.timeStamp,
        delta: value,
        event: event,
        shifted: group.shifted,
      ), group.count);
    }
  }

  void _accept(
    PointerScrollEvent event, {
    required bool shifted,
    required WheelTargetForAxis targetFor,
  }) {
    final delta = event.scrollDelta;
    final time = event.timeStamp;
    var group = _current;
    if (group != null &&
        group.closed &&
        group.direction == 0 &&
        (!group.waiting || group.count < 3)) {
      group = null;
    }
    final dominant = _dominant(delta, shifted);
    // 단발 휠의 idle 뒤에도 정렬 중인 반대 축 스파이크 하나는 전달하지 않는다.
    if (group == null && _queue.isEmpty && _settlingGroup?.axis != dominant) {
      group = _settlingGroup;
    }
    // 요일 정렬 중에도 휠 세션은 먼저 끝날 수 있다. 이때 Shift를 떼고 아래로
    // 굴린 첫 칸은 세로 입력으로 받아 두었다가 도착한 요일의 끼니로 전달한다.
    if (group != null && group.closed && group.shifted != shifted) group = null;
    final axis = group?.axis ?? dominant;
    final value = _component(delta, axis, group?.shifted ?? shifted);
    final sample = (time: time, delta: value, event: event, shifted: shifted);
    if (group != null && group.direction != 0) {
      final restart = _handleCommittedInput(group, sample);
      if (restart != null) {
        _start(
          restart.axis,
          restart.samples.last.shifted,
          targetFor,
          restart.samples,
        );
      } else if (value != 0) {
        _observe(group, tail: true);
      }
      return;
    }
    if (group != null && group.waiting) {
      // 도착 페이지가 본문에서 얼마나 소비할지 모르므로 두 축 모두 보관한다.
      group.pending.add(sample);
      if (value != 0) _observe(group);
    } else if (value != 0) {
      if (group == null) {
        _start(axis, shifted, targetFor, [sample]);
      } else {
        _append(group, sample);
      }
    }
  }

  _Restart? _handleCommittedInput(_WheelGroup group, _Sample sample) {
    switch (_classify(group, sample)) {
      case _ContinueGroup():
        return null;
      case final _Restart restart:
        return restart;
      case _ReverseAlignment(:final page):
        final position = group.position!;
        group.target!.motion.alignWheel(position, page);
        _committed(group, position, page, -group.direction, sample.time);
        return null;
    }
  }

  _WheelDecision _classify(_WheelGroup group, _Sample sample) {
    final axis = group.axis;
    final otherAxis = axis == Axis.horizontal ? Axis.vertical : Axis.horizontal;
    final other = _component(sample.event.scrollDelta, otherAxis, false);
    final value = sample.delta;
    if (!sample.shifted &&
        !group.shifted &&
        other.abs() >= 3 * math.max(1, value.abs())) {
      return _crossAxis(group, otherAxis, (
            time: sample.time,
            delta: other,
            event: sample.event,
            shifted: false,
          )) ??
          const _ContinueGroup();
    }
    group.cross.clear();
    group.softRead = false;
    if (value == 0) return const _ContinueGroup();
    final history = group.history;
    final settled = _settlingGroup == null;
    final pairAfterArrival = settled && group.previousSampleSettled;
    group.previousSampleSettled = settled;
    history.removeWhere(
      (p) => sample.time - p.time > const Duration(milliseconds: 136),
    );
    history.add(sample);
    if (value * group.direction < 0) {
      // 정렬이 끝나도 프레임 끝까지 _settlingGroup이 남을 수 있어 실제 스크롤 상태도 본다.
      // 도착한 뒤에는 첫 반대 입력부터 본문에 전달해야 조금만 위로 굴려도 읽던 위치로 돌아간다.
      final position = group.position!;
      if (_settlingGroup != group ||
          !(position.context.notificationContext?.mounted ?? false) ||
          !position.isScrollingNotifier.value) {
        return _restartOnInputAxis(group, [sample]);
      }
      group.reverse += value.abs();
      if (ResistantPageMotion.shouldCommitWheel(
        sample.event.kind,
        value.abs(),
        group.reverse,
      )) {
        final direction = axisDirectionIsReversed(position.axisDirection)
            ? -group.direction
            : group.direction;
        return _ReverseAlignment(group.page - direction);
      }
    } else {
      group.reverse = 0;
      if (sample.time - group.committed >= const Duration(milliseconds: 110) &&
          _accelerated(group.history, group.direction)) {
        // 주 경계에서는 두 값이 모두 요일 정렬 후에 들어와야 새 당김을 시작한다.
        // 정렬 도중부터 커진 값까지 쓰면 일요일로 넘어간 동작만으로 다음 주가 열린다.
        if (group.weekEdge && !pairAfterArrival) {
          history.clear();
          return const _ContinueGroup();
        }
        final pair = history.sublist(history.length - 2);
        if (pair.first.shifted != sample.shifted) return const _ContinueGroup();
        return _restartOnInputAxis(group, pair);
      }
    }
    return const _ContinueGroup();
  }

  _Restart _restartOnInputAxis(_WheelGroup group, List<_Sample> samples) {
    final last = samples.last;
    if (last.shifted == group.shifted) {
      return _Restart(group.axis, samples);
    }
    final axis = _dominant(last.event.scrollDelta, last.shifted);
    // 새 동작을 승인한 뒤에는 이전 그룹의 가로 이동량을 세로 본문에 전달하지 않는다.
    return _Restart(axis, [
      for (final s in samples)
        (
          time: s.time,
          delta: _component(s.event.scrollDelta, axis, s.shifted),
          event: s.event,
          shifted: s.shifted,
        ),
    ]);
  }

  _Restart? _crossAxis(_WheelGroup group, Axis axis, _Sample sample) {
    group.reverse = 0;
    final cross = group.cross;
    if (cross.isNotEmpty &&
        (sample.time - cross.last.time > _pairGap ||
            sample.delta * cross.last.delta <= 0)) {
      cross.clear();
      group.softRead = false;
    }
    if (!group.softRead) {
      cross.removeWhere((s) => sample.time - s.time > _crossWindow);
    }
    cross.add(sample);
    if (cross.length >= 2 &&
        (sample.delta + cross[cross.length - 2].delta).abs() >=
            ResistantPageMotion.commitDistance) {
      return _Restart(
        axis,
        group.softRead ? List.of(cross) : cross.sublist(cross.length - 2),
      );
    }
    if (axis == Axis.vertical) {
      final total = cross.fold(0.0, (n, s) => n + s.delta.abs());
      final largest = cross.fold(0.0, (n, s) => math.max(n, s.delta.abs()));
      group.softRead |= total >= 30 && total - largest >= 10;
      if (group.softRead && _settlingGroup == null) return _bodyInput(group);
    }
    return null;
  }

  static bool _accelerated(List<_Sample> h, double direction) {
    // 단일 피크는 버리고, 연속 두 값 모두 직전 96ms 중앙값을 넘어야 한다.
    if (h.length < 4) return false;
    final a = h[h.length - 2], b = h.last;
    if (b.time - a.time > _pairGap || a.delta * direction <= 0) {
      return false;
    }
    final prior = [
      for (final s in h.take(h.length - 2))
        if (a.time - s.time <= const Duration(milliseconds: 96))
          math.max(0.0, s.delta * direction),
    ]..sort();
    if (prior.length < 2) return false;
    final median =
        (prior[(prior.length - 1) ~/ 2] + prior[prior.length ~/ 2]) / 2;
    return math.min(a.delta.abs(), b.delta.abs()) >= 2.8 * math.max(12, median);
  }

  _Restart? _bodyInput(_WheelGroup group) {
    final samples = group.cross;
    final total = samples.fold(0.0, (n, s) => n + s.delta);
    final canRead =
        group.targetFor(Axis.vertical)?.canRead?.call(total) ?? false;
    final result = canRead ? _Restart(Axis.vertical, List.of(samples)) : null;
    group.softRead = false;
    samples.clear();
    return result;
  }

  void _start(
    Axis axis,
    bool shifted,
    WheelTargetForAxis targetFor,
    List<_Sample> samples,
  ) {
    // 가로 이동 중 세로 입력의 목적 본문은 정렬 뒤 처음 배치될 수 있다.
    if ((_settlingGroup == null || axis == Axis.horizontal) &&
        targetFor(axis) == null) {
      return;
    }
    _settlingGroup?.softRead = false;
    _settlingGroup?.cross.clear();
    final old = _current;
    if (old != null) _close(old, allowWeekChange: false);
    _idle?.cancel();
    _guard?.cancel();
    final group = _WheelGroup(
      axis,
      shifted,
      targetFor,
      _settlingGroup != null || _queue.isNotEmpty,
    );
    _current = group;
    if (group.waiting) _queue.add(group);
    for (final s in samples) {
      _append(group, s);
    }
  }

  void _append(_WheelGroup group, _Sample s) {
    // 웹 트랙패드에서 받은 25px 두 건을 합치면 마우스 휠 한 칸(50px)으로 판정할 수 있다.
    // 본문이 배치될 때까지 각 이벤트의 두 축을 그대로 보관해 도착한 순서대로 판정한다.
    if (!group.waiting && !_readyForWheel(group)) {
      group.waiting = true;
      _queue.add(group);
    }
    if (group.waiting) {
      group.pending.add(s);
    } else {
      _deliver(group, s);
    }
    _observe(group);
    if (group.waiting && _settlingGroup == null) _drainQueue();
  }

  void _observe(_WheelGroup group, {bool tail = false}) {
    if (_current != group) return;
    group.count++;
    final boundary = group.target?.isWeekBoundary?.call() ?? false;
    final idle = boundary || group.count == 1
        ? singleIdleDuration
        : burstIdleDuration;
    // 이미 확정한 페이지의 관성은 입력 잠금을 연장할 필요가 없다.
    // 주 경계에서는 기존의 관성 종료 시점을 유지한다.
    if (!group.closed && (!tail || group.weekEdge)) {
      _idle?.cancel();
      _idle = Timer(idle, () {
        final active = _current;
        if (active != null) _close(active);
      });
    }
    _guard?.cancel();
    final longGuard =
        (group.direction != 0 || group.pending.isNotEmpty) &&
        group.count >= 3 &&
        !group.weekEdge;
    _guard = Timer(longGuard ? _guardDuration : idle, () {
      final active = _current;
      _current = null;
      if (active != null) _close(active);
    });
  }

  void _deliver(_WheelGroup group, _Sample s) {
    var target = group.target;
    if (target == null) {
      target = group.targetFor(group.axis);
      if (target == null) return;
      group.target = target;
      final generation = _generation;
      target.motion.onWheelCommit = (position, page, direction, time) {
        if (generation == _generation) {
          _committed(group, position, page, direction, time);
        }
      };
    }
    // 휠은 스크롤할 방향을, 드래그는 손가락이 움직인 방향을 나타내므로 부호를 뒤집는다.
    // kind는 원래 이벤트의 값을 유지한다. 웹에서는 트랙패드의 휠 이벤트도 mouse일 수 있다.
    final delta = group.axis == Axis.horizontal
        ? Offset(-s.delta, 0)
        : Offset(0, -s.delta);
    target.move(
      DragUpdateDetails(
        kind: s.event.kind,
        sourceTimeStamp: s.time,
        delta: delta,
        primaryDelta: -s.delta,
        globalPosition: s.event.position,
        localPosition: s.event.localPosition,
      ),
      !group.queued,
    );
  }

  void _committed(
    _WheelGroup group,
    ScrollPosition position,
    double page,
    double direction,
    Duration time,
  ) {
    _untrack();
    group.position = position;
    group.page = page;
    group.direction = direction;
    group.committed = time;
    group.previousSampleSettled = false;
    group.reverse = 0;
    group.history.clear();
    group.cross.clear();
    group.softRead = false;
    group.weekEdge =
        group.target?.isWeekEdgePage?.call(position, page) ?? false;
    if (position.isScrollingNotifier.value) {
      _settlingGroup = group;
      position.isScrollingNotifier.addListener(_activityChanged);
    }
  }

  void _activityChanged() {
    final group = _settlingGroup;
    if (group == null || group.position!.isScrollingNotifier.value) return;
    final generation = _generation;
    // 탭 인덱스와 도착 본문의 레이아웃이 반영된 뒤 전달한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _generation ||
          _settlingGroup != group ||
          group.position!.isScrollingNotifier.value) {
        return;
      }
      _untrack();
      if (group.softRead && (_current == group || _current == null)) {
        final body = _bodyInput(group);
        if (body != null) {
          _start(body.axis, false, group.targetFor, body.samples);
        }
      }
      _drainQueue();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _readyForWheel(_WheelGroup group) {
    final target = group.target ?? group.targetFor(group.axis);
    return target?.readyForWheel?.call() ?? true;
  }

  void _drainQueue() {
    while (_settlingGroup == null && _queue.isNotEmpty) {
      final group = _queue.first;
      final target = group.target ?? group.targetFor(group.axis);
      if (target == null) {
        // 배치 전에 뷰가 교체되면 이전 입력의 목적지가 사라진다.
        // 이 그룹이 아직 입력을 소유한 경우에만 타이머와 축 잠금을 해제한다.
        _queue.removeFirst();
        if (_current == group) {
          _idle?.cancel();
          _guard?.cancel();
          _current = null;
        }
        continue;
      }
      if (target.readyForWheel?.call() == false) {
        if (!_layoutRetryScheduled) {
          _layoutRetryScheduled = true;
          final generation = _generation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (generation != _generation) return;
            _layoutRetryScheduled = false;
            _drainQueue();
          });
          WidgetsBinding.instance.scheduleFrame();
        }
        return;
      }
      _replay(_queue.removeFirst());
    }
  }

  void _replay(_WheelGroup group) {
    group.waiting = false;
    while (group.pending.isNotEmpty) {
      final original = group.pending.removeFirst();
      final sample = (
        time: original.time,
        delta: _component(
          original.event.scrollDelta,
          group.axis,
          group.shifted,
        ),
        event: original.event,
        shifted: original.shifted,
      );
      if (group.direction == 0) {
        if (sample.delta != 0) _deliver(group, sample);
        continue;
      }
      final restart = _handleCommittedInput(group, sample);
      if (restart == null) continue;
      // 정렬을 기다리던 동안 다음 스와이프까지 들어왔을 수 있다.
      final next = _WheelGroup(
        restart.axis,
        restart.samples.last.shifted,
        group.targetFor,
        true,
      );
      next.pending.addAll(restart.samples);
      next.pending.addAll(group.pending);
      next.closed = group.closed;
      next.count = next.pending
          .where(
            (s) =>
                _component(s.event.scrollDelta, next.axis, next.shifted) != 0,
          )
          .length;
      if (_current == group) _current = next;
      group.pending.clear();
      group.closed = true;
      _queue.addFirst(next);
    }
    if (group.closed) group.target?.finish(false);
  }

  void _untrack() {
    _settlingGroup?.position?.isScrollingNotifier.removeListener(
      _activityChanged,
    );
    _settlingGroup = null;
  }

  void _close(_WheelGroup group, {bool allowWeekChange = true}) {
    if (group.closed) return;
    group.closed = true;
    final scope = group.weekPullScope;
    if (!allowWeekChange && scope != null) _weekPullTails[scope] = null;
    group.target?.finish(allowWeekChange);
  }

  // 탭을 직접 누르거나 새 드래그를 시작하면 이전 당김은 끝난 것으로 본다.
  // 미리보기가 열릴 때는 이력을 유지해야 남은 관성이 월요일을 넘기지 않는다.
  static void clearWeekPull(NavigatorState? navigator) {
    if (navigator != null) _weekPullTails[navigator] = null;
  }

  void reset({NavigatorState? clearWeekPullIn}) {
    clearWeekPull(clearWeekPullIn);
    _generation++;
    _layoutRetryScheduled = false;
    _untrack();
    _idle?.cancel();
    _guard?.cancel();
    _queue.clear();
    final group = _current;
    _current = null;
    if (group != null) _close(group, allowWeekChange: false);
  }

  void detach(WheelScrollTarget target) {
    if (_current?.target == target) {
      reset();
    } else if (_settlingGroup?.target == target) {
      _untrack();
      // 사라진 뷰의 정렬만 끝낸다. 이미 대기 중인 새 입력은 다음 화면에서 처리한다.
      if (_queue.isNotEmpty) {
        final generation = _generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (generation == _generation) _drainQueue();
        });
        WidgetsBinding.instance.scheduleFrame();
      }
    }
  }
}
